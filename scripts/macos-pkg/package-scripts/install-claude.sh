touch "$SELECTION_ROOT/install-claude"
chmod a+r "$SELECTION_ROOT/install-claude"
"$SCRIPT_DIR/installer-session-helper.sh" install-integrations "$ONLYMACS_INSTALLER_INTEGRATION_ROOT" claude
