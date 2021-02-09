use adblock::lists::{FilterFormat, FilterSet, RuleTypes, parse_filter, ParsedFilter};
use adblock::optimizer::optimize;
use adblock::filters::network::NetworkFilter;
use std::os::raw::{c_char};
use std::ffi::{CString, CStr};
use serde_json;

#[no_mangle]
pub extern fn parse_easylist(to: *const c_char) -> *const c_char {
    let c_str = unsafe { CStr::from_ptr(to) };
    let mut filter_set = FilterSet::new(true);
    let recipient = c_str.to_str().unwrap();
    filter_set.add_filter_list(recipient, FilterFormat::Standard);
    let (rules, _) = filter_set.into_content_blocking(RuleTypes::All).unwrap();
    let serialized_rules = serde_json::to_string(&rules).unwrap_or("[]".to_string());
    CString::new(serialized_rules.to_owned()).unwrap().into_raw()
}

#[no_mangle]
pub extern fn free_contentlist(s: *mut c_char) {
    unsafe {
        if s.is_null() { return }
        CString::from_raw(s)
    };
}