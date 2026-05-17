rm -rf "$SELECTION_ROOT"
mkdir -p "$SELECTION_ROOT"
cat > "$SELECTION_ROOT/seed-present" <<EOF
version=$BUILD_VERSION
build=$BUILD_NUMBER
channel=$BUILD_CHANNEL
EOF
chmod -R a+rX "$SELECTION_ROOT"
"$SCRIPT_DIR/installer-session-helper.sh" reset-install-state
