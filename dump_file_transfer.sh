UNIQ=sychenn
REMOTE_HOST="$UNIQ@login.engin.umich.edu"    
REMOTE_DIR="/home/$UNIQ/eecs470/p4-f25.group14/dump_files"  
LOCAL_DIR="/mnt/c/Users/user/Desktop/umich/EECS470/GUI_Debuggger_github/EECS470_GUI_DEBUGGER/dump_files"
mkdir -p "$LOCAL_DIR"

rsync -avz --progress \
  --include='*/' --include='*.json' --exclude='*' \
  "$REMOTE_HOST:$REMOTE_DIR/" "$LOCAL_DIR/"
