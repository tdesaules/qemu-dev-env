#!/bin/bash

# --- NORD COLOR PALETTE (True Color) ---
NC='\033[0m'
BOLD='\033[1m'
# Snow Storm (Textes)
WHITE='\033[38;2;216;222;233m'  # Nord4 : #D8DEE9
# Frost (Blues/Cyans)
FROST_1='\033[38;2;143;188;187m' # Nord7 : #8FBCBB (Cyan)
FROST_2='\033[38;2;136;192;208m' # Nord8 : #88C0D0 (Light Blue)
FROST_3='\033[38;2;129;161;193m' # Nord9 : #81A1C1 (Medium Blue)
FROST_4='\033[38;2;94;129;172m'  # Nord10: #5E81AC (Dark Blue)
# Aurora (Colors)
RED='\033[38;2;191;97;106m'      # Nord11: #BF616A
ORANGE='\033[38;2;208;135;112m'   # Nord12: #D08770
YELLOW='\033[38;2;235;203;139m'   # Nord13: #EBCB8B
GREEN='\033[38;2;163;190;140m'    # Nord14: #A3BE8C
MAGENTA='\033[38;2;180;142;173m'  # Nord15: #B48EAD

_log() {
    local LEVEL=$1
    local MSG=$2
    local TIME=$(date +"%H:%M:%S")
    local COLOR=$NC
    local ICON="  "
    case " ${LEVEL} " in
        " title ")    COLOR=$MAGENTA;   ICON="        󰄾 " ;;
        " debug ")    COLOR=$WHITE;     ICON="         " ;;
        " info ")     COLOR=$FROST_2;   ICON="          " ;;
        " notice ")   COLOR=$FROST_1;   ICON="        " ;;
        " success ")  COLOR=$GREEN;     ICON="       " ;;
        " warning ")  COLOR=$YELLOW;    ICON="       " ;;
        " error ")    COLOR=$ORANGE;    ICON="         " ;;
        " critical ") COLOR=$RED;       ICON="      " ;;
    esac
    echo -e "${WHITE}[ $TIME ]${NC} ${COLOR}${BOLD}[ ${LEVEL,,} ]${NC} ${COLOR}$ICON ${MSG,,}${NC}"
}

_error_handler() {
    local MESSAGE="${1}"
    _log "critical" "${MESSAGE}"
    exit 1
}
