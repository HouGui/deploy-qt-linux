#!/bin/bash
# Script to deploy the Qt dependencies of a binary to a directory.
# Usage example: ./deploy_qt_linux.sh ./bin/my-binary ./deploy /path/to/qtpaths true

# Exit immediately if any command within the script returns a non-zero exit status
set -e

# Check if the correct number of arguments are passed
if [[ $# -ne 4 ]]; then
    echo "Usage: $0 <binary_path> <deploy_dir> <qtpaths_path> <exclude_lib_pattern>"
    exit 1
fi

# Path of the binary to deploy the Qt dependencies for.
BINARY_PATH="$1"
# Directory to deploy the Qt dependencies to, e.g. CMake install directory.
DEPLOY_DIR="$2"
# Path to the qtpaths executable.
QTPATHS_PATH="$3"
# Option to exclude standard C/C++ libraries from deployment.
EXCLUDE_STD_LIBS="$4"
 
# Creates necessary directories for deployment.
create_directories() {
    mkdir -p "${DEPLOY_DIR}/lib"
    mkdir -p "${DEPLOY_DIR}/plugins"
}

# Gets the Qt plugins directory.
get_qt_plugins_dir() {
    echo "$("$QTPATHS_PATH" -query QT_INSTALL_PLUGINS)"
}

# Checks and copies dependencies of a file.
copy_dependencies() {
    local FILE="$1"
    local DEPLOY_DIR="$2"
    local EXCLUDE_STD_LIBS="$3"

    echo "Copying dependencies of $FILE..."
    ldd "$FILE" | grep "=>" | awk '{ print $3 }' | while read -r LIB; do
        if [[ -n "$LIB" && -f "$LIB" && ! "$LIB" =~ incos ]]; then
            TARGET_LIB="${DEPLOY_DIR}/lib/$(basename "$LIB")"
            
            # Exclude if standard library and EXCLUDE_STD_LIBS is true
            if [[ $EXCLUDE_STD_LIBS == true && ( "$LIB" =~ libstdc\+\+\.so.* || "$LIB" =~ libc\.so.* ) ]]; then
                continue
            fi

            # Copy the dependency if it's not already copied or is different
            if [[ ! -f "$TARGET_LIB" ]] || ! cmp -s "$LIB" "$TARGET_LIB"; then
                mkdir -p "$(dirname "$TARGET_LIB")"
                cp "$LIB" "$TARGET_LIB"
                echo "Copied dependency library: $LIB to ${DEPLOY_DIR}/lib"
            fi
        fi
    done
}

# Copies Qt plugins and their dependencies.
copy_qt_plugins() {
    local PLUGIN_DIR="$1"
    local REL_PATHS="$2"
    local DEPLOY_DIR="$3"

    # Split the relative paths into directory and mode
    IFS=',' read -r SUBDIR MODE <<< "$REL_PATHS"

    # Determine source and destination directories
    local SRC_DIR="${PLUGIN_DIR}/${SUBDIR}"
    local DEST_DIR="${DEPLOY_DIR}/plugins/${SUBDIR}"

    mkdir -p "$DEST_DIR"

    if [[ "$MODE" == "all" ]]; then
        copy_all_files "$SRC_DIR" "$DEST_DIR" "$DEPLOY_DIR"
    elif [[ "$MODE" =~ ^\[.*\]$ ]]; then
        copy_specific_files "$SRC_DIR" "$DEST_DIR" "$DEPLOY_DIR" "${MODE//[\[\]]/}"
    else
        echo "Error: Invalid mode specified for $REL_PATHS"
    fi
}

# Copies all files from a source to a destination.
copy_all_files() {
    local SRC_DIR="$1"
    local DEST_DIR="$2"
    local DEPLOY_DIR="$3"

    if [[ -d "$SRC_DIR" ]]; then
        echo "-- Copying all files from $SRC_DIR to $DEST_DIR"
        for FILE in "$SRC_DIR"/*; do
            if [[ -f "$FILE" ]]; then
                cp "$FILE" "$DEST_DIR"
                copy_dependencies "$FILE" "$DEPLOY_DIR" "$EXCLUDE_STD_LIBS"                
            fi
        done
    else
        echo "Error: Directory $SRC_DIR does not exist"
    fi
}

# Copies specific files from source to destination.
copy_specific_files() {
    local SRC_DIR="$1"
    local DEST_DIR="$2"
    local DEPLOY_DIR="$3"
    local FILES="$4"

    for FILE in $FILES; do
        SRC_FILE="$SRC_DIR/$FILE"
        if [[ -f "$SRC_FILE" ]]; then
            echo "-- Copying file $SRC_FILE to $DEST_DIR"
            cp "$SRC_FILE" "$DEST_DIR"
            copy_dependencies "$SRC_FILE" "$DEPLOY_DIR" "$EXCLUDE_STD_LIBS"
        else
            echo "Error: File $SRC_FILE does not exist"
        fi
    done
}

# ===============================
# Main process
# ===============================

echo -e "\n---------------------------------------------------------------------------"
echo -e "Deploying the Qt dependencies of \"$BINARY_PATH\" to" \
        "\"$DEPLOY_DIR/\"..."
echo "    - qtpaths executable: $QTPATHS_PATH"
echo -e "---------------------------------------------------------------------------\n"

# Create necessary directories
create_directories

# Copy binary dependencies to the lib directory
copy_dependencies "$BINARY_PATH" "$DEPLOY_DIR" "$EXCLUDE_STD_LIBS"

# Get Qt plugins directory
QT_PLUGINS_DIR=$(get_qt_plugins_dir)

# Selected Qt plugin paths to deploy
QT_PLUGIN_REL_PATHS=( 
    "imageformats,all"
    "platforminputcontexts,all"
    "platforms,[libqxcb.so]"
    "platformthemes,[libqxdgdesktopportal.so]"
    "xcbglintegrations,all"
)

# Copy Qt plugins to the deployment directory
echo -e "\nDeploying the Qt plugins from \"$QT_PLUGINS_DIR\"..."
for REL_PATHS in "${QT_PLUGIN_REL_PATHS[@]}"; do
    copy_qt_plugins "$QT_PLUGINS_DIR" "$REL_PATHS" "$DEPLOY_DIR"
done

echo -e "\nQt dependencies and plugins deployed successfully.\n"
