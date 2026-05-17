touch "$SELECTION_ROOT/install-codex"
chmod a+r "$SELECTION_ROOT/install-codex"
"$SCRIPT_DIR/installer-session-helper.sh" install-integrations "$ONLYMACS_INSTALLER_INTEGRATION_ROOT" codex
