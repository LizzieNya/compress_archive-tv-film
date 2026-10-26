#!/usr/bin/env bash
set -uo pipefail

# ----- CONFIG -----
PIXELDRAIN_API_KEY="YOUR_API_KEY"
DEFAULT_FOLDER="$(pwd)"
XZ_BIN="xz"
# ------------------

shopt -s nullglob nocaseglob

has_gui() {
    [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]] && command -v zenity >/dev/null 2>&1
}

msg_info() {
    if has_gui; then zenity --info --title="Info" --text="$1" --width=360 2>/dev/null
    else echo -e "\n[INFO] $1\n"; fi
}

msg_error() {
    if has_gui; then zenity --error --title="Error" --text="$1" --width=360 2>/dev/null
    else echo -e "\n[ERROR] $1\n" >&2; fi
}

compress_files() {
    local folder="$1"
    local delete_orig="$2"
    local files=("$folder"/*.mp4 "$folder"/*.mkv)

    if [[ ${#files[@]} -eq 0 ]]; then
        msg_info "No .mp4 or .mkv files found in:\n$folder"
        return
    fi

    for f in "${files[@]}"; do
        echo "Compressing: $f"
        if [[ "$delete_orig" == "true" ]]; then
            "$XZ_BIN" -9e -T0 "$f"
        else
            "$XZ_BIN" -9e -T0 --keep "$f"
        fi
    done
    msg_info "Compression complete (${#files[@]} file(s))."
}

decompress_files() {
    local folder="$1"
    local files=("$folder"/*.mp4.xz "$folder"/*.mkv.xz)

    if [[ ${#files[@]} -eq 0 ]]; then
        msg_info "No .mp4.xz or .mkv.xz files found in:\n$folder"
        return
    fi

    for f in "${files[@]}"; do
        echo "Decompressing: $f"
        "$XZ_BIN" -d -T0 --keep "$f"
    done
    msg_info "Decompression complete (${#files[@]} file(s))."
}

upload_pixeldrain() {
    local filepath="$1"
    if [[ ! -f "$filepath" ]]; then
        msg_error "File not found: $filepath"
        return
    fi

    local filename
    filename=$(basename "$filepath")
    local encoded_name
    encoded_name=$(curl -Gso /dev/null -w %{url_effective} --data-urlencode "f=$filename" "" | cut -d'=' -f2-)

    local resp
    resp=$(curl -sS -X PUT -u ":$PIXELDRAIN_API_KEY" \
        --upload-file "$filepath" \
        "https://pixeldrain.com/api/file/$encoded_name")

    local id
    id=$(echo "$resp" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

    if [[ -n "$id" ]]; then
        local url="https://pixeldrain.com/u/$id"
        if command -v xclip >/dev/null 2>&1; then
            printf "%s" "$url" | xclip -selection clipboard
        elif command -v wl-copy >/dev/null 2>&1; then
            printf "%s" "$url" | wl-copy
        fi
        msg_info "Uploaded!\nLink: $url"
    else
        msg_error "Upload failed:\n$resp"
    fi
}

download_pixeldrain() {
    local file_id="$1"
    local dest_folder="$2"
    mkdir -p "$dest_folder"

    local info
    info=$(curl -sS -u ":$PIXELDRAIN_API_KEY" "https://pixeldrain.com/api/file/$file_id/info")
    local filename
    filename=$(echo "$info" | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    [[ -z "$filename" ]] && filename="${file_id}.bin"

    local out_path="$dest_folder/$filename"
    if curl -fL -u ":$PIXELDRAIN_API_KEY" -o "$out_path" "https://pixeldrain.com/api/file/$file_id"; then
        msg_info "Downloaded to:\n$out_path"
    else
        msg_error "Download failed for ID: $file_id"
    fi
}

# ----- MAIN LOOP (GUI OR CLI) -----
if has_gui; then
    while true; do
        ACTION=$(zenity --list --title="XZ Batch Archive & Pixeldrain" \
            --width=480 --height=280 \
            --column="Action" --column="Description" \
            "Compress"   "Compress all *.mp4 / *.mkv in a folder (.xz)" \
            "Decompress" "Decompress all *.mp4.xz / *.mkv.xz in a folder" \
            "Upload"     "Upload a file to Pixeldrain" \
            "Download"   "Download a file from Pixeldrain by ID" 2>/dev/null) || exit 0

        case "$ACTION" in
            "Compress")
                FOLDER=$(zenity --file-selection --directory --title="Select Target Folder" --filename="$DEFAULT_FOLDER/" 2>/dev/null) || continue
                DEL="false"
                if zenity --question --title="Delete Originals?" --text="Delete original .mp4/.mkv files after compression?" --width=360 2>/dev/null; then
                    DEL="true"
                fi
                compress_files "$FOLDER" "$DEL"
                ;;
            "Decompress")
                FOLDER=$(zenity --file-selection --directory --title="Select Target Folder" --filename="$DEFAULT_FOLDER/" 2>/dev/null) || continue
                decompress_files "$FOLDER"
                ;;
            "Upload")
                FILE=$(zenity --file-selection --title="Pick File to Upload" --filename="$DEFAULT_FOLDER/" 2>/dev/null) || continue
                upload_pixeldrain "$FILE"
                ;;
            "Download")
                FILE_ID=$(zenity --entry --title="Download from Pixeldrain" --text="Enter Pixeldrain File ID:" 2>/dev/null) || continue
                [[ -z "$FILE_ID" ]] && continue
                DEST=$(zenity --file-selection --directory --title="Select Save Folder" --filename="$DEFAULT_FOLDER/" 2>/dev/null) || continue
                download_pixeldrain "$FILE_ID" "$DEST"
                ;;
        esac
    done
else
    # Fallback TUI for headless Linux / SSH sessions
    while true; do
        echo "=== XZ Batch Compress/Decompress with Pixeldrain ==="
        echo "1) Compress (*.mp4/*.mkv)"
        echo "2) Decompress (*.xz)"
        echo "3) Upload file to Pixeldrain"
        echo "4) Download from Pixeldrain"
        echo "5) Quit"
        read -rp "Select option [1-5]: " opt
        case "$opt" in
            1)
                read -rp "Target folder [$DEFAULT_FOLDER]: " folder
                folder="${folder:-$DEFAULT_FOLDER}"
                read -rp "Delete originals after compression? (y/N): " del
                [[ "$del" =~ ^[Yy]$ ]] && compress_files "$folder" "true" || compress_files "$folder" "false"
                ;;
            2)
                read -rp "Target folder [$DEFAULT_FOLDER]: " folder
                decompress_files "${folder:-$DEFAULT_FOLDER}"
                ;;
            3)
                read -rp "File path to upload: " filepath
                upload_pixeldrain "$filepath"
                ;;
            4)
                read -rp "Pixeldrain File ID: " fid
                read -rp "Save folder [$DEFAULT_FOLDER]: " dest
                download_pixeldrain "$fid" "${dest:-$DEFAULT_FOLDER}"
                ;;
            5) exit 0 ;;
        esac
    done
fi
