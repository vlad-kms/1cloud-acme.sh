#!/usr/bin/env sh

#
#OC_Key="sdfsdfsdfljlbjkljlkjsdfoiwje"
#

OC_Api="https://api.1cloud.ru/dns"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_1cloud_add() {
  fulldomain=$1
  txtvalue=$2

  OC_Key="${OC_Key:-$(_readaccountconf_mutable OC_Key)}"

  if [ -z "$OC_Key" ]; then
    OC_Key=""
    _err "You don't specify 1cloud.ru api key yet."
    _err "Please create you key and try again."
    return 1
  fi

  #save the api key to the account conf file.
  _saveaccountconf_mutable OC_Key "$OC_Key"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _info "Adding record"
  #if _oc_rest POST "/$_domain_id/records/" "{\"type\": \"TXT\", \"ttl\": 60, \"name\": \"$fulldomain\", \"content\": \"$txtvalue\"}"; then
  if _oc_rest POST "recordtxt/" "{\"DomainId\": \"$_domain_id\", \"TTL\": 60, \"Name\": \"$fulldomain\", \"Text\": \"$txtvalue\"}"; then
    if _contains "$response" "$txtvalue" || _contains "$response" 'Подобная запись для данного домена уже существует'; then
      _info "Added, OK"
      # HACK если раскомментировать, то в основной скрипт в $dns_entry к имени _acme-challenge.domain.dd добавиться символ '.' 
      #dns_entry=$(echo $dns_entry |sed -nE "s/([^,]*,)([^,]*)(,.*)/\1\2.\3/pg")
      return 0
    fi
  fi
  _err "Add txt record error."
  return 1
}

#fulldomain txtvalue
dns_1cloud_rm() {
  fulldomain=$1
  txtvalue=$2

  OC_Key="${OC_Key:-$(_readaccountconf_mutable OC_Key)}"

  if [ -z "$OC_Key" ]; then
    OC_Key=""
    _err "You don't specify 1cloud api key yet."
    _err "Please create you key and try again."
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"
  _debug "Getting txt records"
  #####################################
  # инфа о корневом домене и его записях
  _oc_rest GET "/${_domain_id}"
  _debug3 response "$response"
  if ! _contains "$response" "$txtvalue"; then
    _err "Txt record not found"
    return 1
  fi
  # все ресурсные записи домена
  _record_all=$( echo "$response"   | sed -nE "s/.*(\"LinkedRecords\" *: *\[)([^]]*)\].*/\2/p")
  _debug2 "_record_all" "$_record_all"
  if [ -z "$_record_all" ]; then
    _err "can not find _record_all"
    return 1
  fi
  # ресурсная запись TXT acme*
  _record_seg=$(echo "$_record_all" | sed -nE "s/.*([^{]*\"ID[^}]*\"Text\" *: *\"..$txtvalue[^}]*).*/\1/p")
  #_record_seg="$(echo "$response" | _egrep_o "[^{]*\"content\" *: *\"$txtvalue\"[^}]*}")"
  _debug2 "_record_seg" "$_record_seg"
  if [ -z "$_record_seg" ]; then
    _err "can not find _record_seg"
    return 1
  fi
  # id записи
  _record_id=$(echo "$_record_seg"   | sed -nE "s/.*\"ID\" *: *([[:digit:]]*).*/\1/p")
  #_record_id="$(echo "$_record_seg" | tr "," "\n" | tr "}" "\n" | tr -d " " | grep "\"id\"" | cut -d : -f 2)"
  _debug2 "_record_id" "$_record_id"
  if [ -z "$_record_id" ]; then
    _err "can not find _record_id"
    return 1
  fi

  if ! _oc_rest DELETE "/$_domain_id/$_record_id"; then
    _err "Delete record error."
    return 1
  fi
  return 0
}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_id=sdjkglgdfewsdfg
_get_root() {
  # проверить установлен ли jq
  jq --version > /dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    _err "error Reguired installed jq"
    is_jq=0
    #return 1
  else
    is_jq=1
  fi;
  # HACK установка в 0 отменяет применение jq даже при его наличии
  #is_jq=0
  _debug "Installed jq is" $is_jq

  domain=$1
  # список доменов от 1Cloud
  if ! _oc_rest GET "/"; then
    return 1
  fi
  # они поддерживают только домены 2-го уровня, поэтому корневой - это name.dom
  # получаем корневой для переданной записи
  old_IFS=$IFS
  IFS='.' read -ra arr_dom <<< "$domain"
  IFS=$old_IFS
  s="${#arr_dom[*]}"
  li=$(( $s - 1 ))
  _d="${arr_dom[(( $li - 1 ))]}.${arr_dom[$li]}"
  # _sub_domain
  _sd=''
  for (( i = 0; i < $(( $s - 2 )); i++ )); do
    _sd="${_sd}.${arr_dom[$i]}"
  done
  _sd=${_sd:1:${#_sd}}
  # надо найти запись для домена среди полученных доменов от провайдера в $response и в ней ID
  # response='[{"ID":34124,"Name":"mrovo.ru",..., {"ID":341244,"Name":"mrovo.ru",...}]'
  # _domain_id
  if [[ $is_jq -eq 1 ]]; then
    c=$(echo "$response" | jq '.| length')
    for (( i = 0; i < ${c}; i++ )); do
      e=$((echo "$response" | jq ".[$i]") | jq '.Name' | sed -nE "s/([\"]*)([^\"]*).*/\2/p")
      if [ "$e" = "$_d" ]; then
        _domain_id=$((echo "$response" | jq ".[$i]") | jq '.ID')
        break
      fi
    done
  else
    _domain_id=$(echo "$response" | sed -nE "s/.*(\"ID\":)([[:digit:]]*)(.\"Name\":\"$_d\").*/\2/p")
  fi
  if [[ -z $_domain_id ]]; then
    _err "error NOT domain ID"
    return 1
  fi
  _domain=$_d
  _sub_domain=$_sd
  return 0
}

_oc_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  export _H1="Authorization: ""Bearer $OC_Key"""
  export _H2="Content-Type: application/json"

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$OC_Api/$ep" "" "$m")"
  else
    response="$(_get "$OC_Api/$ep")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
