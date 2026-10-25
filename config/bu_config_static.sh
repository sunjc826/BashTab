# Constants and the settings of the built-in static config phase "static",
# registered here and nowhere else. The entrypoint resolves them once per
# shell, before almost all of BashTab runs (exported values > the static
# settings file bu_config_local.static.sh > the registered --default), then
# exports them: they stay final for the life of the shell.

BU_LOG_LVL_TRACE=0
BU_LOG_LVL_DEBUG=1
BU_LOG_LVL_INFO=2
BU_LOG_LVL_WARN=3
BU_LOG_LVL_ERR=4
BU_LOG_LVL_SILENCE=99

BU_TERMINAL_EDITOR_PREFERENCE=(vi nano vim emacs)
BU_VISUAL_EDITOR_PREFERENCE=(code codium)

# Root output directory. BU_CACHE_DIR, BU_LOG_DIR, BU_TMP_DIR, and
# BU_HISTORY all derive from this (see bu_core_base.sh).
bu_config_register BU_OUT_DIR --default "/tmp/bu/$USER" \
    --hint "Root output directory (cache, logs, tmp, history)"

# Verbose bootstrap logging ("sourcing ..." lines during activation).
bu_config_register BU_BOOTSTRAP_VERBOSE --bool --default false \
    --hint "Verbose logging during activation bootstrap"

bu_config_register BU_EXIT_HANDLER_VSCODE_POPUP --bool --default false \
    --hint "Offer a VS Code popup for the failing frame when a command fails"

# Set to false to force a full command scan on every activation.
# Use in environments where available commands change per shell
# (dynamic module systems, rapid development).
bu_config_register BU_COMMAND_CACHE_ENABLED --bool --default true \
    --hint "Cache the command registry between activations (false: scan every time)"

# Bootstrap inputs: they choose the settings files and modules themselves, so
# only the environment (or the activate script) can set them.
bu_config_register BU_CONFIG_LOCAL_FILE --env-only \
    --hint "Settings file written by bu set-config (default: config/bu_config_local.sh)"
bu_config_register BU_TOP_LEVEL_MODULE --env-only \
    --hint "Top-level module: the command-cache key and prompt name"
bu_config_register BU_MODULE_LIST --env-only \
    --hint "Registered modules, name:version:preinit_path;..."
bu_config_register BU_MODULE_DEPS --env-only \
    --hint "Module requirements recorded by bu_module_require, parent>dep;..."
