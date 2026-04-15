use blst::*;
use std::ffi::CString;
use std::os::raw::c_char;
use std::sync::Mutex;

static LAST_ERROR: Mutex<Option<String>> = Mutex::new(None);

fn set_error(msg: String) {
    *LAST_ERROR.lock().unwrap() = Some(msg);
}

#[no_mangle]
pub extern "C" fn groth16_last_error() -> *const c_char {
    match LAST_ERROR.lock().unwrap().take() {
        Some(msg) => {
            let c = CString::new(msg).unwrap();
            c.into_raw() as *const c_char
        }
        None => std::ptr::null(),
    }
}

/// Compress a G1 affine point from two 48-byte big-endian field elements
/// into 48 bytes of compressed form.
#[no_mangle]
pub extern "C" fn groth16_g1_compress(
    x_ptr: *const u8,
    x_len: usize,
    y_ptr: *const u8,
    y_len: usize,
    out_ptr: *mut u8,
    out_len: usize,
) -> i32 {
    if x_len != 48 || y_len != 48 || out_len < 48 {
        set_error("g1_compress: invalid buffer sizes".into());
        return -1;
    }
    unsafe {
        let x_slice = std::slice::from_raw_parts(x_ptr, 48);
        let y_slice = std::slice::from_raw_parts(y_ptr, 48);
        let out_slice = std::slice::from_raw_parts_mut(out_ptr, 48);

        let mut x = blst_fp::default();
        let mut y = blst_fp::default();
        blst_fp_from_bendian(&mut x, x_slice.as_ptr());
        blst_fp_from_bendian(&mut y, y_slice.as_ptr());

        let affine = blst_p1_affine { x, y };

        // Convert affine → projective (Z=1)
        let mut proj = blst_p1::default();
        blst_p1_from_affine(&mut proj, &affine);

        let mut compressed = [0u8; 48];
        blst_p1_compress(compressed.as_mut_ptr(), &proj);
        out_slice.copy_from_slice(&compressed);
    }
    0
}

/// Compress a G2 affine point from four 48-byte big-endian field elements
/// (x0, x1, y0, y1 where Fp2 = c0 + c1*u) into 96 bytes of compressed form.
#[no_mangle]
pub extern "C" fn groth16_g2_compress(
    x0_ptr: *const u8,
    x0_len: usize,
    x1_ptr: *const u8,
    x1_len: usize,
    y0_ptr: *const u8,
    y0_len: usize,
    y1_ptr: *const u8,
    y1_len: usize,
    out_ptr: *mut u8,
    out_len: usize,
) -> i32 {
    if x0_len != 48 || x1_len != 48 || y0_len != 48 || y1_len != 48 || out_len < 96 {
        set_error("g2_compress: invalid buffer sizes".into());
        return -1;
    }
    unsafe {
        let x0_slice = std::slice::from_raw_parts(x0_ptr, 48);
        let x1_slice = std::slice::from_raw_parts(x1_ptr, 48);
        let y0_slice = std::slice::from_raw_parts(y0_ptr, 48);
        let y1_slice = std::slice::from_raw_parts(y1_ptr, 48);
        let out_slice = std::slice::from_raw_parts_mut(out_ptr, 96);

        let mut x0 = blst_fp::default();
        let mut x1 = blst_fp::default();
        let mut y0 = blst_fp::default();
        let mut y1 = blst_fp::default();
        blst_fp_from_bendian(&mut x0, x0_slice.as_ptr());
        blst_fp_from_bendian(&mut x1, x1_slice.as_ptr());
        blst_fp_from_bendian(&mut y0, y0_slice.as_ptr());
        blst_fp_from_bendian(&mut y1, y1_slice.as_ptr());

        let x = blst_fp2 { fp: [x0, x1] };
        let y = blst_fp2 { fp: [y0, y1] };

        let affine = blst_p2_affine { x, y };

        // Convert affine → projective (Z=1)
        let mut proj = blst_p2::default();
        blst_p2_from_affine(&mut proj, &affine);

        let mut compressed = [0u8; 96];
        blst_p2_compress(compressed.as_mut_ptr(), &proj);
        out_slice.copy_from_slice(&compressed);
    }
    0
}
