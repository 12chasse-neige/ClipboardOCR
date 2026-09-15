#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if [[ "$(uname -m)" != arm64 || "$(uname -s)" != Darwin ]]; then
    print -u2 "Clipboard OCR requires macOS on Apple Silicon."
    exit 1
fi
if (( ${$(sw_vers -productVersion)%%.*} < 26 )); then
    print -u2 "This pinned MLX runtime requires macOS 26 or later."
    exit 1
fi
runtime_root="$HOME/Library/Application Support/ClipboardOCR"
export UV_PYTHON_INSTALL_DIR="$runtime_root/python"
export UV_CACHE_DIR="$HOME/Library/Caches/ClipboardOCR/uv"
uv_path="${commands[uv]:-$HOME/.local/bin/uv}"
if [[ ! -x "$uv_path" ]]; then
    print -u2 "Install uv first from https://docs.astral.sh/uv/getting-started/installation/ then run this command again."
    exit 1
fi
if pgrep -x ClipboardOCR > /dev/null; then
    print -u2 "Quit Clipboard OCR before updating its runtime."
    exit 1
fi
"$uv_path" python install 3.12.13
python_path="$("$uv_path" python find 3.12.13 --managed-python)"
for component in pipeline mlx; do
    env_name=runtime
    [[ "$component" == mlx ]] && env_name=runtime-mlx
    "$uv_path" venv --clear --python "$python_path" "$runtime_root/$env_name"
    "$uv_path" pip sync --python "$runtime_root/$env_name/bin/python" --require-hashes "backend/requirements-$component.lock"
    "$uv_path" pip check --python "$runtime_root/$env_name/bin/python"
done
"$runtime_root/runtime/bin/python" scripts/download_models.py
"$runtime_root/runtime/bin/python" scripts/verify_setup.py
print "Setup complete. Open dist/Clipboard OCR.app."
