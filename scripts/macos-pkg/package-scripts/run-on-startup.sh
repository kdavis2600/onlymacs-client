touch "$SELECTION_ROOT/run-on-startup"
chmod a+r "$SELECTION_ROOT/run-on-startup"
"$SCRIPT_DIR/installer-session-helper.sh" install-launch-at-login "$ONLYMACS_INSTALLER_APP_PATH"
