#!/bin/bash

directory="/boot/loader/entries"

# Change to new, unconventional directory
change_directory() {
  # If current argument is not empty and is directory, set new directory.
  if [ -n "${!cur_arg_pos}" ] && [ -d "${!cur_arg_pos}" ]; then
      directory="${!cur_arg_pos}"
  else
    echo "[ERROR: -b]: Directory \"${!cur_arg_pos}\" not found."
    exit 1
  fi
}

# Finds entries out in console.
find_entry() {
  local file="$1"
  title=$(awk '$1 == "title" { $1=""; sub(/^ +/, ""); sub(/ +$/, ""); print }' "$file")
  version=$(awk '$1 == "version" { $1=""; sub(/^ +/, ""); sub(/ +$/, ""); print }' "$file")
  linux=$(awk '$1 == "linux" { $1=""; sub(/^ +/, ""); sub(/ +$/, ""); print }' "$file")
  title="${title//$'\r'/}"
  version="${version//$'\r'/}"
  linux="${linux//$'\r'/}"
}

# List entries sorted by given flag or only those with corresponding kernel/title regex value.
list_entries() {
  next_arg_pos=$((cur_arg_pos + 1))
  case "${!cur_arg_pos}" in

    ""|"-f")
      # Looks for files with .conf in $directory and sorts them by name.
      find "$directory" -type f -name "*.conf" | sort | while read -r file; do
        find_entry "$file"
        echo "$title ($version, $linux)"
      done
      cur_arg_pos=$((cur_arg_pos + 1))
      ;;

    "-s")
      # Looks for files with .conf in $directory and sorts them by sort-key value.
      grep -H "sort-key" "$directory"/*.conf | \
        sed -n 's/^\(.*\):.*sort-key \(.*\)$/\2 \1/p' | \
        sort -k1,1 -k2,2 | \
        while read -r key file; do
          find_entry "$file"
          echo "$title ($version, $linux)"
        done

      # Looks for files with .conf in $directory withnout sort-key value.
      grep -L "sort-key" "$directory"/*.conf | sort | while read -r file; do
        find_entry "$file"
        echo "$title ($version, $linux)"
      done
      cur_arg_pos=$((cur_arg_pos + 1))
      ;;

    "-k")
      if [ -n "${!next_arg_pos}" ]; then
        # Goes through every file and searches for given pattern in kernel value.
        for file in "$directory"/*.conf; do
          [ -f "$file" ] || continue
          find_entry "$file"
          if [[ "$linux" =~ ${!next_arg_pos} ]]; then
            echo "$title ($version, $linux)"
          fi
        done
      else
        echo "[ERROR: list -k]: Regular expression for kernel missing."
        exit 1
      fi
      cur_arg_pos=$((cur_arg_pos + 2))
      ;;

    "-t")
      if [ -n "${!next_arg_pos}" ]; then
        # Goes through every file in $directory and searches for given pattern in title value.
        for file in "$directory"/*.conf; do
          [ -f "$file" ] || continue
          find_entry "$file"
          if [[ "$title" =~ ${!next_arg_pos} ]]; then
            echo "$title ($version, $linux)"
          fi
        done
      else
        echo "[ERROR: list -t]: Regular expression for title missing."
        exit 1
      fi
      cur_arg_pos=$((cur_arg_pos + 2))
      ;;

    *)
      echo "[ERROR: list]: Unknown list flag \"${!cur_arg_pos}\"."
      exit 1
      ;;
  esac
}

remove_entries() {
  if [ -n "${!cur_arg_pos}" ]; then
    # Goes through every file in $directory and searches for given pattern in title value.
    for file in "$directory"/*.conf; do
      [ -f "$file" ] || continue
      title=$(awk '$1 == "title" { $1=""; sub(/^ /, ""); print }' "$file")
      title="${title//$'\r'/}"
      if [[ "$title" =~ ${!cur_arg_pos} ]]; then
        rm "$file"
      fi
    done
  else
    echo "[ERROR: remove]: Regular expression for title missing."
    exit 1
  fi
}

duplicate_entries() {
  current_default=$(grep -l 'vutfit_default y' "$directory"/*.conf 2>/dev/null | head -n 1)

  index=$cur_arg_pos

  # Looks for <entry_file_path>, deletes the argument after retrieval. <entry_file_path> needs to be in
  # path/to/file.conf format, "/path/to\ file.conf" probably won't work.
  for (( ; index <= $#; index++ )); do
    if [ -f "$directory/${!index}" ] && [ "$(eval echo \${$((index - 1))})" != "-d" ]; then
      echo "HERE"
      file="${!index}"
      set -- "${@:1:index-1}" "${@:index+1}"
      break
    fi
  done
  if [ -z "$file" ] && [ -n "$current_default" ]; then
    file=$(basename "$current_default")
  elif [ -z "$file" ] && [ -z "$current_default" ]; then
    echo "[ERROR: duplicate]: Missing filepath or default entry."
    exit 1
  fi

  filename=""
  content="$(<"$directory/$file")"
  content="$(echo "$content" | sed -E 's/^vutfit_default[[:space:]]+[yn]/vutfit_default n/')"

  while [ -n "${!cur_arg_pos}" ]; do
    next_arg_pos=$((cur_arg_pos + 1))
    case "${!cur_arg_pos}" in

      "-k")
        echo "KERNEL"
        if [ -n "${!next_arg_pos}" ]; then
          kernel_path="${!next_arg_pos}"
          content="$(echo "$content" | sed -E "s|^linux .*|linux $kernel_path|")"
        else
          echo "[ERROR: duplicate -k]: Regular expression for kernel missing."
          exit 1
        fi
        cur_arg_pos=$((cur_arg_pos + 2))
        ;;

      "-i")
        if [ -n "${!next_arg_pos}" ]; then
          initramfs_path="${!next_arg_pos}"
          content="$(echo "$content" | sed -E "s|^initrd .*|initrd $initramfs_path|")"
        else
          echo "[ERROR: duplicate -i]: Regular expression for initramfs missing."
          exit 1
        fi
        cur_arg_pos=$((cur_arg_pos + 2))
        ;;

      "-t")
        if [ -n "${!next_arg_pos}" ]; then
          new_title="${!next_arg_pos}"
          content="$(echo "$content" | sed -E "s|^title .*|title $new_title|")"
        else
          echo "[ERROR: duplicate -t]: Regular expression for title missing."
          exit 1
        fi
        cur_arg_pos=$((cur_arg_pos + 2))
        ;;

      "-a")
        if [ -n "${!next_arg_pos}" ]; then

          new_argument="${!next_arg_pos}"

          if [[ "$content" != *"options"*"$new_argument"* ]]; then
            new_content=""
            while IFS= read -r line; do
              if [[ "$line" == options* ]]; then
                  line="$line $new_argument"
              fi
              new_content+="$line"$'\n'
            done <<< "$content"
            content="$new_content"
          fi
        else
          echo "[ERROR: duplicate -a]: Missing command-line arguments."
          exit 1
        fi
        cur_arg_pos=$((cur_arg_pos + 2))
        ;;

      "-r")
        if [ -n "${!next_arg_pos}" ]; then

          old_argument="${!next_arg_pos}"

          new_content=""
          while IFS= read -r line; do
            if [[ "$line" == options* ]]; then
              if [[ "$old_argument" == *=* ]]; then
                  line=$(echo "$line" | sed -E "s/\<${old_argument}\>//g")
              else
                  line=$(echo "$line" | sed -E "s/\<${old_argument}(=[^ ]*)?\>//g")
              fi
              line=$(echo "$line" | tr -s ' ')
              line="${line#"${line%%[![:space:]]*}"}"
              line="${line%"${line##*[![:space:]]}"}"
            fi
            new_content+="$line"$'\n'
          done <<< "$content"
          content="$new_content"
        else
          echo "[ERROR: duplicate -r]: Missing command-line arguments."
          exit 1
        fi
        cur_arg_pos=$((cur_arg_pos + 2))
        ;;

      "-d")
        full_path="${!next_arg_pos}"

        if [ -d "$(dirname "$full_path")" ]; then
          new_dest=$(dirname "$full_path")
          filename=$(basename "$full_path")
        else
          echo "[ERROR: duplicate -d]: Missing path to the output log file."
          exit 1
        fi
        cur_arg_pos=$((cur_arg_pos + 2))
        ;;

      "--make-default")
        content="$(echo "$content" | sed -E 's/^vutfit_default[[:space:]]+[yn]/vutfit_default y/')"

        for file in "$directory"/*; do
          [[ ! -f "$file" ]] && continue
          sed -i -E 's/^vutfit_default[[:space:]]+[yn]/vutfit_default n/' "$file"
        done
        cur_arg_pos=$((cur_arg_pos + 1))
        ;;

      *)
        echo "[ERROR: duplicate]: Unknown duplicate flag \"${!cur_arg_pos}\"."
        exit 1
        ;;
    esac
  done

  if [ -d "$new_dest" ]; then

    if [ -z "$dir_name" ]; then
      dir_name="$PWD"  # Pokud je dir_name prázdné, použij aktuální pracovní adresář.
    fi

    dest_file="$dir_name/${filename}"
    cat <<EOF > "$dest_file"
$content
EOF
  elif [ -z "$new_dest" ]; then

    base_name=$(basename "$file" .conf)
    dir_name=$(dirname "$file")
    dest_file="$dir_name/${base_name}-copy-$(date +%s).conf"
    cat <<EOF > "$dest_file"
$content
EOF
  else
    echo "[ERROR: duplicate]: Creating new file failed."
  fi

  cur_arg_pos=$((cur_arg_pos + 1))
}

# Shows default entry, exits if not found.
show_default_entry() {
  default_entry=$(grep -l 'vutfit_default y' "$directory"/*.conf | head -n 1)
  if [ "${!cur_arg_pos}" != "-f" ] && [ -n "$default_entry" ]; then
    cat "$default_entry"; echo
  elif [ "${!cur_arg_pos}" == "-f" ] && [ -n "$default_entry" ]; then
    echo "$default_entry"
    cur_arg_pos=$((cur_arg_pos + 1))
  elif [ -z "$default_entry" ]; then
    echo "[ERROR: show-default]: Missing path or default entry."
    exit 1
  fi
}

# Makes given entry default.
make_default_entry() {
  if [ -z "${!arg_position}" ]; then
    echo "[ERROR: make-default]: Missing path to the file to be set as default."
    exit 1
  fi
  if [ ! -f "${!arg_position}" ]; then
    echo "[ERROR: make-default]: File ${!arg_position} not found."
    exit 1
  fi

  current_default=$(grep -l 'vutfit_default y' "$directory"/*.conf | head -n 1)

  if [ -n "$current_default" ]; then
    sed -i -E 's/^vutfit_default[[:space:]]+[yn]/vutfit_default n/' "$current_default"
  fi
  sed -i -E 's/^vutfit_default[[:space:]]+[yn]/vutfit_default y/' "${!arg_position}"

  cur_arg_pos=$((cur_arg_pos + 2))
}


if [ ! -d "$directory" ] && [ "$1" != "-b" ]; then
  echo "[ERROR]: Directory $directory not found."
  exit 1
fi

if [ "$#" -eq 0 ]; then
  echo "[ERROR]: No arguments provided."
  exit 1
fi

cur_arg_pos=1
# Main while loop
while [ $cur_arg_pos -le $# ]; do
  case "${!cur_arg_pos}" in
    -b)
      cur_arg_pos=$((cur_arg_pos + 1))
      change_directory "$@"
      cur_arg_pos=$((cur_arg_pos + 1))
      ;;
    list)
      cur_arg_pos=$((cur_arg_pos + 1))
      list_entries "$@"
      ;;
    remove)
      cur_arg_pos=$((cur_arg_pos + 1))
      remove_entries "$@"
      cur_arg_pos=$((cur_arg_pos + 1))
      ;;
    duplicate)
      cur_arg_pos=$((cur_arg_pos + 1))
      duplicate_entries "$@"
      ;;
    show-default)
      cur_arg_pos=$((cur_arg_pos + 1))
      show_default_entry "$@"
      ;;
    make-default)
      cur_arg_pos=$((cur_arg_pos + 1))
      make_default_entry "$@"
      ;;
    *)
      echo "[ERROR]: Unknown command \"${!cur_arg_pos}\"."
      exit 1
      ;;
  esac
done















