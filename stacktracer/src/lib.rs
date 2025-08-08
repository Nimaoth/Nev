use std::ptr;
use std::ffi::CString;
use std::ffi::c_char;
use std::backtrace::Backtrace;

#[unsafe(no_mangle)]
pub unsafe extern "C" fn stacktracer_print_stacktrace() {
    let backtrace = Backtrace::force_capture();
    eprintln!("{}", backtrace);
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn stacktracer_get_stacktrace() -> *const c_char {
    let backtrace = Backtrace::force_capture();
    let backtrace = format!("{}", backtrace);
    match CString::new(backtrace) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => ptr::null(),
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn stacktracer_free_stacktrace(str: *mut c_char) {
    if !str.is_null() {
        unsafe {
            let _ = CString::from_raw(str);
        }
    }
}
