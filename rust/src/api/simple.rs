#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    // Habilita o tratamento padrão de panics e logs do flutter_rust_bridge.
    flutter_rust_bridge::setup_default_user_utils();
}
