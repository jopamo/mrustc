#!/usr/bin/env python3
import sys
from pathlib import Path


def replace_once(path: Path, old: str, new: str) -> None:
    data = path.read_text()
    if new in data:
        return
    if old not in data:
        raise SystemExit(f"{path}: expected source snippet not found")
    path.write_text(data.replace(old, new, 1))


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <rust-src-dir>", file=sys.stderr)
        return 1

    root = Path(sys.argv[1])

    lib_rs = root / "compiler" / "rustc_target" / "src" / "lib.rs"
    compile_rs = root / "src" / "bootstrap" / "src" / "core" / "build_steps" / "compile.rs"

    replace_once(
        lib_rs,
        """    match option_env!("CFG_LIBDIR_RELATIVE") {\n        None | Some("lib") => {\n            if sysroot.join(PRIMARY_LIB_DIR).join(RUST_LIB_DIR).exists() {\n                PRIMARY_LIB_DIR.into()\n            } else {\n                SECONDARY_LIB_DIR.into()\n            }\n        }\n        Some(libdir) => libdir.into(),\n    }\n""",
        """    match option_env!("CFG_LIBDIR_RELATIVE") {\n        Some(libdir) if libdir != "lib" => libdir.into(),\n        _ => {\n            let primary = sysroot.join(PRIMARY_LIB_DIR);\n            let secondary = sysroot.join(SECONDARY_LIB_DIR);\n\n            if primary.join(RUST_LIB_DIR).exists() {\n                match (primary.canonicalize(), secondary.canonicalize()) {\n                    (Ok(primary_real), Ok(secondary_real)) if primary_real == secondary_real => {\n                        SECONDARY_LIB_DIR.into()\n                    }\n                    _ => PRIMARY_LIB_DIR.into(),\n                }\n            } else {\n                SECONDARY_LIB_DIR.into()\n            }\n        }\n    }\n""",
    )

    replace_once(
        compile_rs,
        """            let stage0_lib_dir = builder.out.join(host).join("stage0/lib");\n            t!(fs::create_dir_all(sysroot.join("lib")));\n            builder.cp_link_r(&stage0_lib_dir, &sysroot.join("lib"));\n\n            // Copy codegen-backends from stage0\n            let sysroot_codegen_backends = builder.sysroot_codegen_backends(compiler);\n            t!(fs::create_dir_all(&sysroot_codegen_backends));\n            let stage0_codegen_backends = builder\n                .out\n                .join(host)\n                .join("stage0/lib/rustlib")\n                .join(host)\n                .join("codegen-backends");\n""",
        """            let stage0_libdir = &builder.build.initial_relative_libdir;\n            let stage0_lib_dir = builder.out.join(host).join("stage0").join(stage0_libdir);\n            t!(fs::create_dir_all(sysroot.join(stage0_libdir)));\n            builder.cp_link_r(&stage0_lib_dir, &sysroot.join(stage0_libdir));\n\n            // Copy codegen-backends from stage0\n            let sysroot_codegen_backends = builder.sysroot_codegen_backends(compiler);\n            t!(fs::create_dir_all(&sysroot_codegen_backends));\n            let stage0_codegen_backends = stage0_lib_dir\n                .join("rustlib")\n                .join(host)\n                .join("codegen-backends");\n""",
    )

    replace_once(
        compile_rs,
        """            if builder.local_rebuild {\n                // On local rebuilds this path might be a symlink to the project root,\n                // which can be read-only (e.g., on CI). So remove it before copying\n                // the stage0 lib.\n                let _ = fs::remove_dir_all(sysroot.join("lib/rustlib/src/rust"));\n            }\n\n            builder.cp_link_r(&builder.initial_sysroot.join("lib"), &sysroot.join("lib"));\n""",
        """            let stage0_libdir = &builder.build.initial_relative_libdir;\n\n            if builder.local_rebuild {\n                // On local rebuilds this path might be a symlink to the project root,\n                // which can be read-only (e.g., on CI). So remove it before copying\n                // the stage0 lib.\n                let _ = fs::remove_dir_all(sysroot.join(stage0_libdir).join("rustlib/src/rust"));\n            }\n\n            builder.cp_link_r(\n                &builder.initial_sysroot.join(stage0_libdir),\n                &sysroot.join(stage0_libdir),\n            );\n""",
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
