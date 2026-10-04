//// Node file URL conversion: https://nodejs.org/api/url.html

@external(javascript, "../../url.ffi.mjs", "fileURLToPath")
pub fn file_url_to_path(url: String) -> Result(String, String)
