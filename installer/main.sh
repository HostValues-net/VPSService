writeLog() {
  if [[ $3 == true ]]; then
    reset
  fi
  
  parsedData=("${@:4} ")
  printf "\033[0m#\033[0;4m\033[0;1m\033[0;${2}m${1}\033[0m: ${parsedData[*]}\n\n"
  sleep 1
}

conlog() {
  writeLog LOG 92 true $*
}

coninfo() {
  writeLog INFO 97 true $*
}

connotice() {
  writeLog NOTICE 96 true $*
}

conwarn() {
  writeLog WARN 93 true $*
}

conalert() {
  writeLog ALERT 36 true $*
}

concritical() {
  writeLog CRITICAL 95 true $*
}

conemergency() {
  writeLog EMERGENCY 41 true $*
}

conerror() {
  writeLog ERROR 98 true $*
}

condebug() {
  writeLog DEBUG 92 true $*
}

conlogo() {
  echo -e "/*  
 * 
 * ╭╮╱╭┳━━━┳━━━┳━━━━┳╮╱╱╭┳━━━┳╮╱╱╭╮╱╭┳━━━┳━━━╮
 * ┃┃╱┃┃╭━╮┃╭━╮┃╭╮╭╮┃╰╮╭╯┃╭━╮┃┃╱╱┃┃╱┃┃╭━━┫╭━╮┃
 * ┃╰━╯┃┃╱┃┃╰━━╋╯┃┃╰┻╮┃┃╭┫┃╱┃┃┃╱╱┃┃╱┃┃╰━━┫╰━━╮
 * ┃╭━╮┃┃╱┃┣━━╮┃╱┃┃╱╱┃╰╯┃┃╰━╯┃┃╱╭┫┃╱┃┃╭━━┻━━╮┃
 * ┃┃╱┃┃╰━╯┃╰━╯┃╱┃┃╱╱╰╮╭╯┃╭━╮┃╰━╯┃╰━╯┃╰━━┫╰━╯┃
 * ╰╯╱╰┻━━━┻━━━╯╱╰╯╱╱╱╰╯╱╰╯╱╰┻━━━┻━━━┻━━━┻━━━╯
 *
 * Copyright ©️ 2022 HostValues - All Rights Reserved.
 *
*/"
}

checkRoot() {
  if [[ $EUID -ne 0 ]]; then
    read -p "Do you want to proceed installing as a root user? (y/n)" answer
    case ${answer:0:1} in
    y | Y)
      echo Continuing with installation..
      ;;
    *)
      echo Terminating installation script.;
      exit
      ;;
    esac
  fi
}
