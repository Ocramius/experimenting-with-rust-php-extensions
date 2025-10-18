#![cfg_attr(windows, feature(abi_vectorcall))]
use ext_php_rs::prelude::*;

#[php_function]
pub fn my_custom_extension(name: &str) -> String {
    format!("From my custom extension: {}!", name)
}

#[php_module]
pub fn get_module(module: ModuleBuilder) -> ModuleBuilder {
    module.function(wrap_function!(my_custom_extension))
}
