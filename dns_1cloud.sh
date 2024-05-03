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
  _info "Adding record"
  #if _oc_rest POST "/$_domain_id/records/" "{\"type\": \"TXT\", \"ttl\": 60, \"name\": \"$fulldomain\", \"content\": \"$txtvalue\"}"; then
  if _oc_rest POST "recordtxt/" "{\"DomainId\": \"$_domain_id\", \"TTL\": 60, \"Name\": \"$fulldomain\", \"Text\": \"$txtvalue\"}"; then
    if _contains "$response" "$txtvalue" || _contains "$response" 'Подобная запись для данного домена уже существует'; then
      _info "Added, OK"
      return 0
    fi
  fi
  _err "add txt record error"
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
  _debug "Getting txt records"
  #####################################
  # инфа о корневом домене и его записях
  _oc_rest GET "/${_domain_id}"
  _debug3 response "$response"
  if ! _contains "$response" "$txtvalue"; then
    _err "TXT record not found"
    # нет в ответе txtvalue"
    return 0
  fi
  _record_id=$(echo "$response" | sed -nE "s/.*(\"LinkedRecords\" *: *\[)([^]]*)\].*/\2/p" | sed -nE "s/.*(\{[^{]*\"ID\" *: *([[:digit:]]*),[^}]*\"Text\" *: *\"[\]\"${txtvalue}[^}]*\}).*/\2/p")
  _debug2 "_record_id" "$_record_id"
  if [ -z "$_record_id" ]; then
    _err "can not find _record_id"
    return 0
  fi
  if ! _oc_rest DELETE "/$_domain_id/$_record_id"; then
    _err "delete record error."
    return 1
  fi
  return 0
}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _domain     - корневой домен
# _domain_id  - id домена
_get_root() {
  domain=$1
  # у 1cloud корневым доменом может быть только домен 2-го уровня
  # получаем корневой и субдомен домены для переданной записи
  count_word="$(echo "$domain" | tr '.' ' ' | wc -w)"
  if [ "$count_word" -lt 3 ]; then
    _err "Error domain NAME"
    return 1
  fi
  _domain=$(echo "$domain" | cut -d. -f $(("$count_word"-1))-100)
  _debug _domain "$_domain"
  # список зарегистрированных доменов на 1Cloud
  if ! _oc_rest GET "/"; then
    _err "get domains from hostinger"
    return 1
  fi
  # надо проверить наличие запись для домена среди полученных доменов от провайдера в $response и в ней получить ID
  _domain_id=$(echo "$response" | sed -nE "s/.*(\"ID\":)([[:digit:]]*)(.\"Name\":\"$_domain\").*/\2/p")
  if [ -z "$_domain_id" ]; then
    _err "domain ID: is not"
    return 1
  fi
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
  r="$?"
  if [ "$r" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
