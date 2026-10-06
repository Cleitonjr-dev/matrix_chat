# matrix_chat

Cliente de mensageria desktop desenvolvido em **Flutter**, com a comunicação com um homeserver **Matrix** implementada em **Rust** por meio do **Matrix Rust SDK** e do **Flutter Rust Bridge**.

A aplicação cobre os fluxos essenciais de um cliente de mensagens — autenticação, listagem e seleção de salas, visualização e envio de mensagens (com resposta), atualização em tempo real e encerramento/restauração de sessão — com foco em arquitetura, qualidade de código, segurança e experiência do usuário.

---

## Sumário

1. [Arquitetura](#1-arquitetura)
2. [Decisões técnicas](#2-decisões-técnicas)
3. [Instruções de configuração e execução](#3-instruções-de-configuração-e-execução)
4. [Testes](#4-testes)
5. [Limitações e itens não concluídos](#5-limitações-e-itens-não-concluídos)

---

## 1. Arquitetura

A solução é dividida em duas partes, ligadas por uma ponte FFI:

```
┌───────────────────────────────────────────────────────────────┐
│ Flutter (Windows / macOS / Linux)                             │
│                                                               │
│  View (Widgets)                                               │
│    LoginPage · RoomsPage · ChatPage                           │
│          │                                                    │
│  ViewModel (Riverpod)                                         │
│    AuthController · RoomsController · MessagesController      │
│          │                                                    │
│  Repository (Dart)                                            │
│    AuthRepository · RoomsRepository · ChatRepository          │
│          │                                                    │
│  Bindings geradas (api.dart, models.dart)                     │
└──────────┼────────────────────────────────────────────────────┘
           │ FFI (Flutter Rust Bridge)
┌──────────▼────────────────────────────────────────────────────┐
│ Rust (crate rust_lib_matrix_chat)                             │
│                                                               │
│  api/     — funções `pub async fn` expostas ao Dart           │
│  matrix/  — serviço Matrix (sessão, salas, mensagens, sync)   │
│  models/  — DTOs (SessionInfo, RoomInfo, Message, SyncEvent)  │
│                                                               │
│  matrix-sdk (sqlite + rustls-aws-lc-rs)                       │
└──────────┬────────────────────────────────────────────────────┘
           │ HTTPS
     ┌─────▼─────┐
     │ Homeserver │  (Matrix)
     └───────────┘
```

**Padrão arquitetural:** MVVM + Repository Pattern.

- A **View** não conhece detalhes de rede nem de protocolo.
- O **ViewModel** (Riverpod) expõe estado e ações, sem depender de `BuildContext`.
- O **Repository** abstrai as chamadas às bindings geradas pelo Flutter Rust Bridge.
- Toda a lógica de comunicação com o Matrix fica isolada na camada Rust.

### Estrutura de diretórios

```
lib/
├─ main.dart
└─ src/
   ├─ app.dart
   ├─ core/                 paths.dart · sync_events.dart
   ├─ data/repositories/    auth_repository · rooms_repository · chat_repository
   ├─ features/
   │  ├─ auth/              login_page · auth_controller
   │  ├─ rooms/             rooms_page · rooms_controller
   │  └─ chat/              chat_page · chat_controller
   └─ rust/                 api.dart · models.dart · frb_generated*.dart (bindings geradas)

rust/
├─ Cargo.toml
└─ src/
   ├─ lib.rs
   ├─ api/                  mod.rs · simple.rs (funções `pub async fn`)
   ├─ matrix/               mod.rs (sessão, salas, mensagens, sync)
   ├─ models/               mod.rs (DTOs)
   └─ frb_generated.rs      (gerado pelo codegen)
```

---

## 2. Decisões técnicas

As decisões relevantes estão documentadas em formato ADR (Contexto / Decisão / Alternativas / Consequências).

### D1 — Comunicação com o Matrix em Rust

- **Contexto:** o enunciado exige que a comunicação seja implementada em Rust com o Matrix Rust SDK.
- **Decisão:** toda autenticação, sessão, salas, mensagens e sincronização ficam em Rust; o Dart apenas consome os dados via FFI.
- **Alternativas:** fazer as chamadas HTTP direto do Dart (via um pacote como `matrix_api_lite`). Descartada por não atender à exigência de integração nativa em Rust.
- **Consequências:** as operações de rede ficam fora da *event loop* da UI; a lógica de negócio do protocolo fica centralizada e testável em Rust.

### D2 — Ponte nativa com funções assíncronas (`pub async fn`)

- **Contexto:** o `matrix-sdk` exige um runtime Tokio. O executor padrão do Flutter Rust Bridge 2.13 (`rust-async`) é justamente o Tokio.
- **Decisão:** as funções expostas são `pub async fn`, o que faz o FRB devolver `Future<T>` ao Dart e executar cada chamada em uma *worker thread* do Tokio.
- **Alternativas:** `#[frb(sync)]` com `block_on` interno. Descartada: bloqueava a thread da UI durante chamadas de rede, deixando a janela "não responsiva".
- **Consequências:** a interface não congela durante login/sync; as operações são naturalmente não bloqueantes.

### D3 — Atualização em tempo real via streaming

- **Contexto:** o fluxo "atualização das conversas" precisa refletir novas mensagens sem ação manual do usuário.
- **Decisão:** um loop em background roda `client.sync_stream()` (long-poll contínuo) e, a cada resposta, empurra um evento `rooms_updated` ao Dart via `StreamSink`. No Dart, um `Stream` broadcast (`syncEventsProvider`) notifica as telas de salas e de chat.
- **Alternativas:** *polling* (um `Timer` chamando `sync` periodicamente). Descartada por introduzir latência e requisições desnecessárias.
- **Consequências:** novas mensagens chegam em tempo real; o loop é resiliente (reinicia após logout/login).

### D4 — Gerenciamento de estado com Riverpod + MVVM + Repository

- **Contexto:** a descrição da vaga cita Riverpod como preferência; o enunciado deixa o gerenciamento de estado a critério.
- **Decisão:** Riverpod 3 (`AsyncNotifier`, `AsyncNotifierProvider.family`) combinado a ViewModels e repositórios.
- **Alternativas:** Provider/ChangeNotifier. Funcionalmente equivalente, mas sem o mesmo suporte a estados assíncronos e testabilidade.
- **Consequências:** estado assíncrono tipado (`AsyncValue`), ViewModels testáveis sem depender do FFI.

### D5 — Persistência de sessão (SQLite + `session.json`)

- **Contexto:** o usuário deve poder fechar e reabrir o app sem se autenticar novamente.
- **Decisão:** o estado do `matrix-sdk` é persistido em um store SQLite (feature `sqlite`), e a `MatrixSession` (tokens + `device_id`) é serializada em `session.json` ao lado do store. Na abertura, `restore_session` reconstrói o cliente a partir desse arquivo.
- **Alternativas:** persistir somente em SQLite (sem o arquivo de sessão). A restauração explícita via arquivo é mais previsível e simples de depurar.
- **Consequências:** sessão restaurada automaticamente; o token fica em disco (fora do repositório).

### D6 — Concorrência e ciclo de vida do `Client`

- **Contexto:** as funções assíncronas podem rodar em threads diferentes do Tokio.
- **Decisão:** o `Client` é mantido em um `Mutex<Option<Client>>` global. Acessos capturam um `clone` (o `Client` é `Send + Sync` e barato de clonar).
- **Detalhe técnico:** um `MutexGuard` não é `Send` e não pode atravessar um `.await` — por isso o guard é sempre solto antes de qualquer ponto assíncrono (o valor é clonado em uma variável própria).
- **Consequências:** acesso concorrente seguro e sem risco de *deadlock* acidental.

### D7 — Transporte e armazenamento (TLS rustls + SQLite *bundled*)

- **Contexto:** o app precisa ser multiplataforma (Windows/macOS/Linux) sem dependências nativas de sistema.
- **Decisão:** TLS via `rustls-aws-lc-rs` e SQLite compilado a partir do código-fonte (`bundled-sqlite`).
- **Alternativas:** `native-tls`/OpenSSL (dependência externa por SO) e `sqlite3.lib` do sistema (ausente por padrão no Windows).
- **Consequências:** build reproduzível entre plataformas; sem bibliotecas nativas extras.

### Nota sobre o `matrix-sdk` 0.19

A API recente difere de versões anteriores. Destaques relevantes para este projeto:

- O histórico de mensagens vem do *event cache* (`client.event_cache().room(...)` + `RoomEventCache::events()`), não mais de `room.timeline()`.
- `event_cache().subscribe()` é obrigatório antes do sync — sem isso, o cache não recebe os eventos.
- O nome da sala não é mais `room.name()`; é calculado a partir de `m.room.name` → alias canônico → nome do outro membro (em DM).
- `restore_session` recebe uma `MatrixSession` serializável.

---

## 3. Instruções de configuração e execução

### Pré-requisitos (obrigatórios para rodar)

| Ferramenta | Versão utilizada | Instalação |
|---|---|---|
| Flutter (stable, desktop habilitado) | 3.44.9 | [flutter.dev](https://docs.flutter.dev/get-started/install) |
| Rust (rustup) | 1.99.0 | `winget install --id Rustlang.Rustup -e` (ou [rustup.rs](https://rustup.rs)) |
| Visual Studio com "Desktop development with C++" | 2026 (18.x) | [visualstudio.microsoft.com](https://visualstudio.microsoft.com/downloads/) |
| Git | 2.56.0 | `winget install --id Git.Git -e` |

> Após instalar o Rust, **feche e reabra o terminal** para que `cargo`/`rustc` entrem no PATH.
> O LLVM/clang não é necessário: o codegen do FRB 2.13 faz o parsing em Rust puro (via `cargo expand`).

### Pré-requisitos (somente para desenvolver / regenerar bindings)

O **Flutter Rust Bridge (codegen)** só é necessário para regenerar as bindings Dart após alterar a API em `rust/src/api/`. Para apenas rodar o app, as bindings já estão commitadas em `lib/src/rust/` — não é preciso instalar.

```powershell
cargo install flutter_rust_bridge_codegen --version 2.13.0
```

> A versão do codegen deve casar com a versão fixada no projeto (`flutter_rust_bridge: 2.13.0` em `pubspec.yaml` e `=2.13.0` em `rust/Cargo.toml`).

### Configuração

```powershell
# Instalar as dependências Dart
flutter pub get
```

> ⚠️ O primeiro build demora vários minutos: o `matrix-sdk` + `rustls` + SQLite são compilados a partir do código-fonte em Rust.

### Gerar as bindings (após alterar a API em `rust/src/api/`)

```powershell
flutter_rust_bridge_codegen generate
```

### Executar

```powershell
flutter run -d windows   # ou -d linux / -d macos
```

### Build de release

```powershell
flutter build windows --release
```

### Uso

1. Crie uma conta em um homeserver Matrix (ex.: `https://app.element.io` com o servidor `matrix.org`), caso ainda não tenha uma — o app implementa apenas login, não cadastro.
2. No app, informe o homeserver (ex.: `https://matrix.org`), o **nome de usuário (localpart)** sem o domínio (ex.: `cleitonjr`, não `@cleitonjr:matrix.org`) e a senha.
3. A lista de salas é exibida; selecione uma sala para ver o histórico e enviar mensagens. A sessão é restaurada automaticamente na próxima abertura, e "Sair" encerra a sessão.

> Precisa de uma conta de teste? Entre em contato com o autor, que fornecerá as credenciais.

> ⚠️ Use uma **sala não criptografada** para os testes — a criptografia ponta-a-ponta não foi habilitada (ver §5).

### Dados persistidos em disco

A sessão e o estado do `matrix-sdk` são gravados no diretório de suporte da aplicação (via `getApplicationSupportDirectory`), nos itens:

- `matrix_store/` — store SQLite do `matrix-sdk` (histórico, estado de sync);
- `session.json` — tokens e `device_id` da sessão (`MatrixSession`), usado na restauração.

Apagar esses arquivos equivale a um *logout* local (a sessão no homeserver permanece até ser revogada via "Sair").

---

## 4. Testes

```powershell
# Rust
cd rust
cargo test

# Dart (unidade e widget)
cd ..
flutter test

# Dart (integração, requer um device desktop)
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/simple_test.dart -d windows

# Análise estática
flutter analyze
```

Cobertura:

- **Rust** (`models`): *round-trip* de serialização JSON do DTO `Message`.
- **Dart — ViewModel** (`auth_controller_test`): valida que o `AuthController` restaura `null` sem sessão e expõe a sessão após login, usando um `FakeAuthRepository` (sem tocar no FFI).
- **Dart — widget** (`widget_test`): valida que a `LoginPage` renderiza os campos de autenticação, com o repositório sobrescrito.
- **Dart — integração** (`integration_test/simple_test.dart`): inicia a biblioteca nativa (`RustLib.init`) e valida que a aplicação monta (`App`).

> Os testes de ViewModel/widget usam `ProviderContainer`/`ProviderScope` com `overrides`, evitando carregar a biblioteca nativa no ambiente de teste. Já o teste de integração carrega o FFI de verdade e, por isso, precisa de um device desktop.

---

## 5. Limitações e itens não concluídos

O enunciado deixa claro que não se espera um produto completo, e sim a demonstração de estruturação, priorização e evolução. Abaixo, o que ficou fora do escopo, com a justificativa e o caminho de evolução.

### 5.1 Criptografia ponta-a-ponta (E2EE)

Não habilitada. É a limitação de maior impacto — exige a feature `e2e-encryption` do `matrix-sdk`, além de gestão de chaves de dispositivo, verificação de identidade e backup de chaves.

- **Por que ficou fora:** não está em nenhum dos cinco fluxos obrigatórios e triplicaria o esforço/tempo de compilação.
- **Evolução:** a comunicação já está isolada na camada Rust; habilitar E2EE é uma mudança de feature/configuração, não de arquitetura.

> Consequência prática: salas criptografadas não podem ser lidas até que o E2EE seja habilitado.

### 5.2 Interações de mensagem

| Recurso | Protocolo | Evolução |
|---|---|---|
| Reações (emoji) | `m.reaction` | parsear a relação em `get_messages` + enviar o evento correspondente |
| Editar mensagem | `m.replace` | idem |
| Responder em tópico (thread) | `m.thread` | exige timeline separada por thread (esforço maior) |
| Apagar/redigir | `m.room.redaction` | enviar evento de redação |
| Menções (`@usuário`) | `m.mentions` | incluir mentions no envio |

A resposta (reply, `m.in_reply_to`) **já foi implementada** e estabelece o padrão para lidar com relações — os demais seguem o mesmo caminho.

### 5.3 Mídia e formatação

- **Upload de mídia** (imagens, arquivos, vídeos) — não implementado; hoje apenas texto (`RoomMessageEventContent::text_plain`). Evolução: upload `mxc://` e eventos de mídia.
- **Rich text / markdown** — mensagens enviadas como texto puro.

### 5.4 Gestão de salas

Criar sala, entrar/sair e aceitar/recusar convites não foram implementados — o escopo foi a **listagem e seleção** das salas existentes.

### 5.5 Experiência de interface

- **Read receipts** ("visto por") e **indicador de digitação** — não implementados.
- **Avatares** — não implementados (exigem resolver e baixar `mxc://`).
- **Notificações push** — não implementadas.
- **Editar perfil / presença** — não implementados.

### 5.6 Escala e eficiência

- **Back-pagination** — o histórico mostra apenas as mensagens trazidas pelo sync (`sync_stream`); não busca mensagens antigas (`run_backwards_once`).
- **Sliding Sync** — a sincronização usa o long-poll clássico; o Sliding Sync (mais eficiente para contas com muitas salas) não foi utilizado.
- **Busca de mensagens e Espaços (spaces)** — não implementados.

### 5.7 Outras observações

- **Homeserver padrão fixo** — `https://matrix.org` é usado na restauração de sessão; o ideal é persistir o último homeserver utilizado.
- **Erros em texto cru** — o tratamento usa `error.toString()`; a evolução é mapear `anyhow::Error` para mensagens amigáveis por categoria (credencial, rede, servidor).
- **Validação de plataforma** — o projeto foi executado e validado em **Windows**; o código é multiplataforma (sem código específico de SO), mas macOS/Linux não foram testados neste ambiente.

---

*As limitações acima refletem uma priorização deliberada: os cinco fluxos obrigatórios do enunciado foram implementados de ponta a ponta, e a arquitetura foi preparada para acomodar as evoluções listadas.*
