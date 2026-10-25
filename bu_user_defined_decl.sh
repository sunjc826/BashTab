# Please do not source this file.
# It is only for shellcheck.

# Static user-defined configuration callback scripts/functions.
# These are sourced once during initialization.
declare -g -a BU_USER_DEFINED_STATIC_CONFIGS=()

# Dynamic user-defined configuration callback scripts/functions.
# These are sourced every time the shell sources user-defined configs.
declare -g -a BU_USER_DEFINED_DYNAMIC_CONFIGS=()

# Static user-defined pre-initialization callback scripts/functions.
# These are sourced once before shell initialization.
declare -g -a BU_USER_DEFINED_STATIC_PRE_INIT_ENTRYPOINT_CALLBACKS=()

# Dynamic user-defined post-initialization callback scripts/functions.
# These are sourced after shell initialization.
declare -g -a BU_USER_DEFINED_DYNAMIC_POST_ENTRYPOINT_CALLBACKS=()

# Static user-defined post-initialization callback scripts/functions.
# These are sourced once after shell initialization.
declare -g -a BU_USER_DEFINED_STATIC_POST_ENTRYPOINT_CALLBACKS=()

# User-defined command-to-key conversion functions.
# These functions can customize how commands are converted to completion keys.
declare -g -a BU_USER_DEFINED_COMPLETION_COMMAND_TO_KEY_CONVERSIONS=()

# User-defined autocomplete helper functions.
# These functions provide custom lazy autocompletion behavior.
declare -g -a BU_USER_DEFINED_AUTOCOMPLETE_HELPERS=()

# A custom command line name for bu.
BU_USER_DEFINED_CLI_COMMAND_NAME=
