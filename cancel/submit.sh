#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_FILE="$SCRIPT_DIR/submit.log"

# Find working Python (Windows Store python3 is broken in Git Bash)
PYTHON=""
for py in python3 python; do
    if $py -c "print('ok')" 2>/dev/null | grep -q ok; then
        PYTHON=$py
        break
    fi
done
if [ -z "$PYTHON" ]; then
    echo "ERROR: No working Python found" >&2
    exit 1
fi

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }

# =============================================
# Config
# =============================================
FORM_ID=82988
APRV_APP_ID=82988
STATE=214456
FID_ENC="f03d643e10dbcc06"
PAGE_ENC="9285edf6efc6ff81ab1bca14ab87cc77"
BASE_URL="https://office.chaoxing.com"
CX_UID="${CX_UID:-}"

UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36"
ACCEPT_JSON="Accept: application/json, text/plain, */*"

# 定位信息优先级：环境变量 > cancel/location.json > cancel/office.chaoxing.com.har-1.har
# GitHub Actions 建议用 Secrets/Variables 设置这三个值。
CANCEL_LAT="${CANCEL_LAT:-}"
CANCEL_LNG="${CANCEL_LNG:-}"
CANCEL_ADDRESS="${CANCEL_ADDRESS:-}"

# =============================================
# Cookie & UUID
# =============================================
if [ -n "$CHAOXING_COOKIES" ]; then
    COOKIES="$CHAOXING_COOKIES"
else
    COOKIES=$(cat "$ROOT_DIR/cookies")
fi

UUID=$($PYTHON -c "import uuid; print(uuid.uuid4().hex)")
CANCEL_TIME=$($PYTHON -c "from datetime import datetime, timedelta, timezone; print(datetime.now(timezone.utc).astimezone(timezone(timedelta(hours=8))).strftime('%Y-%m-%d %H:%M'))")

log "========== 开始执行销假提交 =========="
log "UUID: $UUID"
log "销假时间: $CANCEL_TIME"

# =============================================
# Python: all API calls + build save body
# =============================================
log "开始构建提交数据..."

SAVE_BODY=$(CANCEL_TIME="$CANCEL_TIME" FORM_ID="$FORM_ID" APRV_APP_ID="$APRV_APP_ID" \
    STATE="$STATE" FID_ENC="$FID_ENC" PAGE_ENC="$PAGE_ENC" UUID="$UUID" \
    BASE_URL="$BASE_URL" COOKIES="$COOKIES" CX_UID="$CX_UID" \
    UA="$UA" ACCEPT_JSON="$ACCEPT_JSON" SCRIPT_DIR="$SCRIPT_DIR" \
    CANCEL_LAT="$CANCEL_LAT" CANCEL_LNG="$CANCEL_LNG" CANCEL_ADDRESS="$CANCEL_ADDRESS" \
    $PYTHON << 'PYEOF'
import base64, json, os, subprocess, sys, tempfile as _tmp, urllib.parse, zlib
from Crypto.Cipher import AES
from Crypto.Util.Padding import pad, unpad

cancel_time = os.environ['CANCEL_TIME']
form_id = os.environ['FORM_ID']
aprv_app_id = os.environ['APRV_APP_ID']
state = os.environ['STATE']
fid_enc = os.environ['FID_ENC']
page_enc = os.environ['PAGE_ENC']
page_uuid = os.environ['UUID']
base_url = os.environ['BASE_URL']
cookies = os.environ['COOKIES']
uid_raw = os.environ.get('CX_UID') or ''
ua = os.environ['UA']
accept_json = os.environ['ACCEPT_JSON']
script_dir = os.environ['SCRIPT_DIR']

REQUESTURL_BODY = (
    'url=8rC0Ynnzf3EAu5NbMBaFiA%3D%3D'
    '&response=%5B%7B%22compt%22%3A%22editinput%22%2C%22jpath%22%3A%22%24.xh%22%2C%22pcid%22%3A0%2C%22label%22%3A%22%E5%AD%A6%E5%8F%B7%22%2C%22cid%22%3A2%7D%2C%7B%22compt%22%3A%22editinput%22%2C%22jpath%22%3A%22%24.sznj%22%2C%22pcid%22%3A0%2C%22label%22%3A%22%E5%B9%B4%E7%BA%A7%22%2C%22cid%22%3A3%7D%2C%7B%22compt%22%3A%22editinput%22%2C%22jpath%22%3A%22%24.yx%22%2C%22pcid%22%3A0%2C%22label%22%3A%22%E9%99%A2%E7%B3%BB%22%2C%22cid%22%3A4%7D%2C%7B%22compt%22%3A%22editinput%22%2C%22jpath%22%3A%22%24.zy%22%2C%22pcid%22%3A0%2C%22label%22%3A%22%E4%B8%93%E4%B8%9A%22%2C%22cid%22%3A5%7D%2C%7B%22compt%22%3A%22editinput%22%2C%22jpath%22%3A%22%24.bj%22%2C%22pcid%22%3A0%2C%22label%22%3A%22%E7%8F%AD%E7%BA%A7%22%2C%22cid%22%3A6%7D%2C%7B%22compt%22%3A%22editinput%22%2C%22jpath%22%3A%22%24.fdyList%5B0%5D.fdyxm%22%2C%22pcid%22%3A0%2C%22label%22%3A%22%E8%BE%85%E5%AF%BC%E5%91%98%E5%A7%93%E5%90%8D%22%2C%22cid%22%3A7%7D%2C%7B%22compt%22%3A%22editinput%22%2C%22jpath%22%3A%22%24.fdyList%5B0%5D.fdygh%22%2C%22pcid%22%3A0%2C%22label%22%3A%22%E8%BE%85%E5%AF%BC%E5%91%98%E5%B7%A5%E5%8F%B7%22%2C%22cid%22%3A8%7D%5D'
    '&template=0153c4a4f9124606bcf161929d6fcbd602740ffffae7fd8177bff41cf59ca673ef5d34f5042f8a7e8ef2e5622e98c23c95909ff50bb9cce63993492ba229fcdd38685448658e83d04970df6a28fd2fb886c301d1df58a6bbbae8d45b98e5be7b'
    '&id=46059'
    '&urlHeaders=e655acf8738691eed30cb011b8067fdf'
    '&contactMultipleConfig=%7B%7D'
)

LINK_FORM_ID = '753627'
LINK_FORM_ENC = '4a34437fd4aa17c3ff9e424a038a666e'
LINK_AES_KEY = base64.b64decode('ZDI1VE9XVnBTR2x0VlVaRg==')

def get_cookie(name):
    for part in cookies.split(';'):
        part = part.strip()
        if '=' not in part:
            continue
        k, v = part.split('=', 1)
        if k.strip() == name:
            return urllib.parse.unquote(v.strip())
    return ''

uid_raw = uid_raw or get_cookie('oa_uid') or get_cookie('_uid') or get_cookie('UID')
try:
    uid = int(uid_raw)
except Exception:
    raise RuntimeError('缺少用户 UID：请设置 CX_UID，或确保 Cookie 中包含 oa_uid/_uid/UID')


web_apply_url = (
    f'{base_url}/apps/forms/mobile/apply.html?formType=1&from_type=space&formid={form_id}'
    f'&formType=1&uuid={page_uuid}&pageEnc={page_enc}&uid={uid}&aprvAppId={aprv_app_id}'
    f'&id={form_id}&state={state}&fidEnc={fid_enc}&isManager=false'
)

def curl_get(url, referer=None):
    cmd = ['curl', '-s', '--compressed', '-w', '\n%{http_code}', '-X', 'GET', url,
           '-H', accept_json, '-H', f'User-Agent: {ua}',
           '-H', f'Origin: {base_url}', '-H', f'Cookie: {cookies}']
    if referer:
        cmd.extend(['-H', f'Referer: {referer}'])
    result = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8', errors='replace')
    lines = result.stdout.strip().split('\n')
    code = lines[-1] if lines else '0'
    body = '\n'.join(lines[:-1]) if len(lines) > 1 else ''
    return code, body

def curl_post(url, data, referer=None):
    data_file = _tmp.NamedTemporaryFile(mode='w', suffix='.txt', delete=False, encoding='utf-8')
    data_file.write(data)
    data_file.close()
    cmd = ['curl', '-s', '--compressed', '-w', '\n%{http_code}', '-X', 'POST', url,
           '-H', 'Content-Type: application/x-www-form-urlencoded',
           '-H', accept_json, '-H', f'User-Agent: {ua}',
           '-H', f'Origin: {base_url}', '-H', f'Cookie: {cookies}']
    if referer:
        cmd.extend(['-H', f'Referer: {referer}'])
    cmd.extend(['-d', '@' + data_file.name])
    result = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8', errors='replace')
    os.unlink(data_file.name)
    lines = result.stdout.strip().split('\n')
    code = lines[-1] if lines else '0'
    body = '\n'.join(lines[:-1]) if len(lines) > 1 else ''
    return code, body

def get_cookie(name):
    for part in cookies.split(';'):
        part = part.strip()
        if '=' not in part:
            continue
        k, v = part.split('=', 1)
        if k.strip() == name:
            return urllib.parse.unquote(v.strip())
    return ''

def decode_cookie_userinfo(data):
    key = base64.b64decode('anZHRFg2ekNaVmliZmExTA==')
    cipher = AES.new(key, AES.MODE_ECB)
    decrypted = unpad(cipher.decrypt(base64.b64decode(data)), AES.block_size)
    return json.loads(decrypted)

def aes_ecb_encrypt_json(data):
    raw = json.dumps(data, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
    cipher = AES.new(LINK_AES_KEY, AES.MODE_ECB)
    return base64.b64encode(cipher.encrypt(pad(raw, AES.block_size))).decode('ascii')

def aes_ecb_decrypt_json(ciphertext):
    cipher = AES.new(LINK_AES_KEY, AES.MODE_ECB)
    raw = unpad(cipher.decrypt(base64.b64decode(ciphertext)), AES.block_size)
    return json.loads(raw.decode('utf-8'))

def encode_fvd(data):
    json_str = json.dumps(data, ensure_ascii=False, separators=(',', ':'))
    zlib_bytes = zlib.compress(json_str.encode('utf-8'))
    xored = bytes([b ^ 102 for b in zlib_bytes])
    return base64.b64encode(xored).decode('ascii')

def first_val(v):
    if isinstance(v, list):
        return v[0] if v else ''
    return v or ''

def set_values(container, fid, value):
    fid = str(fid)
    if isinstance(container, list):
        for item in container:
            if str(item.get('id')) == fid:
                fields = item.get('fields', [])
                if fields:
                    fields[0]['values'] = [value]
                return
    elif fid in container:
        container[fid]['groupValues'] = [{'values': [[value]], 'isShow': True}]

def load_location():
    location = {
        'lat': os.environ.get('CANCEL_LAT', ''),
        'lng': os.environ.get('CANCEL_LNG', ''),
        'address': os.environ.get('CANCEL_ADDRESS', '')
    }
    if location['lat'] and location['lng'] and location['address']:
        return location
    raise RuntimeError('定位信息为空：请设置 CANCEL_LAT / CANCEL_LNG / CANCEL_ADDRESS')

# ---- Step 0: Get oaUidEnc ----
sys.stderr.write('Getting oaUidEnc...\n')
code, body = curl_get(f'{base_url}/data/common/cookie/userinfo', base_url + '/')
ui_data = json.loads(body)
if not ui_data.get('success'):
    raise RuntimeError(f'cookie/userinfo failed: {body[:200]}')
cookie_info = decode_cookie_userinfo(ui_data['data'])
oa_cookie = cookie_info.get('oaCookieUserInfo', {})
oa_uid_enc = oa_cookie.get('oaUidEnc', '')
uname = get_cookie('oa_name') or oa_cookie.get('oaName') or oa_cookie.get('name') or '姓名'
sys.stderr.write(f'oaUidEnc={oa_uid_enc[:30]}...\n')

# ---- Step 1: Load apply page + verify/info ----
sys.stderr.write('Loading cancel apply page...\n')
code, _ = curl_get(web_apply_url, base_url + '/')
sys.stderr.write(f'Page HTTP {code}\n')

sys.stderr.write('Getting cancel form structure...\n')
verify_url = (
    f'{base_url}/data/approve/apps/forms/fore/user/verify/info'
    f'?formId={form_id}&aprvAppId={aprv_app_id}&formUserId=0'
    f'&fidEnc={fid_enc}&newApply=0&pageEnc={page_enc}'
    f'&manager=1&uuid={page_uuid}&state={state}'
)
code, body = curl_get(verify_url, web_apply_url)
verify_data = json.loads(body)
enc_data = verify_data['data']['encData']
version = verify_data['data']['forms']['version']
updatetime = verify_data['data']['forms']['updatetime']
sys.stderr.write(f'version={version}, updatetime={updatetime}\n')

# ---- Step 2: Get user info ----
sys.stderr.write('Getting user info...\n')
code, body = curl_post(f'{base_url}/front/open/share/apps/forms/fore/events/requesturl', REQUESTURL_BODY, web_apply_url)
requesturl_data = json.loads(body)
if not requesturl_data.get('success'):
    raise RuntimeError(f'requesturl failed: {body[:200]}')
user_info = {}
for item in requesturl_data.get('data', []):
    user_info[str(item.get('cid', ''))] = first_val(item.get('val', ''))
sys.stderr.write('User info loaded.\n')

# ---- Step 3: Get latest leave number/status from linked fields ----
def call_link_field(current_field_id, link_value_field_id, link_value_field_compt):
    filters = {
        'model': 0,
        'filters': [{
            'id': 1,
            'compt': 'contact',
            'statusIds': '',
            'express': '===',
            'range': [],
            'format': '',
            'dynamicDateType': '',
            'val': [uid],
            'target': {'field': {'compt': '', 'innerIndex': 0, 'id': 1}, 'type': 0},
            'currFormValueFieldId': int(current_field_id)
        }]
    }
    params = {
        'formId': LINK_FORM_ID,
        'enc': LINK_FORM_ENC,
        'linkFormValueFieldId': str(link_value_field_id),
        'innerIndex': '0',
        'linkFormValueFieldCompt': link_value_field_compt,
        'valueFieldId': str(link_value_field_id),
        'valueFieldCompt': link_value_field_compt,
        'filters': aes_ecb_encrypt_json(filters),
        'optionSortId': '-3',
        'optionSort': 'desc',
        'optionSortCompt': '',
        'valueNum': '1',
        'pageSize': '1',
        'currentFormId': form_id,
        'currentEnc': page_enc,
        'currentFieldId': str(current_field_id),
        'currentFormType': '1',
        'currentAprvId': aprv_app_id,
        'currentVersion': str(version)
    }
    body = urllib.parse.urlencode(params, safe='')
    code, resp = curl_post(f'{base_url}/data/apps/forms/fore/forms/user/link/field/data', body, web_apply_url)
    data = json.loads(resp)
    if not data.get('success') or not data.get('data', {}).get('detailVal'):
        raise RuntimeError(f'link field failed: {resp[:200]}')
    vals = aes_ecb_decrypt_json(data['data']['detailVal'])
    if not vals:
        raise RuntimeError('link field returned empty values')
    return vals[0].get('val', '')

sys.stderr.write('Getting linked leave number/status...\n')
qjbh = call_link_field(12, 4, 'editinput')
status_val = call_link_field(13, 3, 'numberinput')
try:
    status_val = int(status_val)
except Exception:
    status_val = 1
sys.stderr.write('Linked fields loaded.\n')

location = load_location()

# ---- Step 4: Build formUserData ----
sys.stderr.write('Building formUserData...\n')
form_user_data = []
for item in enc_data:
    new_item = {}
    for k, v in item.items():
        if k in ('fields', 'layoutRatio'):
            continue
        new_item[k] = v
    new_fields = []
    for f in item.get('fields', []):
        nf = dict(f)
        if not nf.get('values'):
            nf['values'] = [{'val': ''}]
        new_fields.append(nf)
    new_item['fields'] = new_fields
    form_user_data.append(new_item)

contact_value = {'puid': uid, 'uname': uname, 'uidEnc': oa_uid_enc}
set_values(form_user_data, 1, contact_value)
for fid, cid in [(2, '2'), (3, '3'), (4, '4'), (5, '5'), (6, '6'), (7, '7'), (8, '8')]:
    set_values(form_user_data, fid, {'val': user_info.get(cid, '')})
set_values(form_user_data, 10, {'val': cancel_time})
set_values(form_user_data, 11, {'val': '否', 'score': 0, 'valShow': '否'})
set_values(form_user_data, 12, {'val': qjbh})
set_values(form_user_data, 13, {'val': status_val})
set_values(form_user_data, 14, location)

fud_json = json.dumps(form_user_data, ensure_ascii=False, separators=(',', ':'))
fud_enc = urllib.parse.quote_plus(fud_json, safe='')
compt_json = json.dumps({'contact1': {'name': '姓名', 'value': uid}}, ensure_ascii=False, separators=(',', ':'))
compt_enc = urllib.parse.quote_plus(compt_json, safe='')

# ---- Step 5: Approvers ----
sys.stderr.write('Calling approvers...\n')
apprv_body = (
    f'state={state}&formId={form_id}&formType=approveForm&aprvAppId={aprv_app_id}'
    f'&formUserId=0&fidEnc={fid_enc}&aprvTypeId=10000'
    f'&organizeId=0&regionOrganizeId=0&roleId=0&loadAprvUserCount=1'
    f'&formUserData={fud_enc}&comptMatchingJson={compt_enc}'
    f'&pageEnc={page_enc}&formData=&approveLaunchUserId='
)
code, body = curl_post(f'{base_url}/data/approve/apps/forms/fore/list/approvers', apprv_body, web_apply_url)
apprv_resp = json.loads(body)
if not apprv_resp.get('success'):
    raise RuntimeError(f'approvers failed: {body[:200]}')
apprv_data = apprv_resp.get('data', {})
sys.stderr.write('Approvers loaded.\n')

user_list_str = apprv_data.get('userList', '[]')
user_dept_json_str = apprv_data.get('userDeptJson', '{}')
condition_id_list = apprv_data.get('conditionIdList', [])
role_list = apprv_data.get('roleList', [])
role_data_str = json.dumps(role_list[0], ensure_ascii=False, separators=(',', ':')) if role_list else '{"roleId":0,"roleName":"","show":false}'
cdtn_id_str = ','.join(str(c) for c in condition_id_list) if condition_id_list else ''

udj_enc = urllib.parse.quote_plus(user_dept_json_str, safe='')
afl_enc = urllib.parse.quote_plus(user_list_str, safe='')
org_enc = urllib.parse.quote_plus('[{"organizeId":0,"organizeName":"","show":false,"type":0},{"organizeId":0,"organizeName":"","show":false,"type":1}]', safe='')
role_enc = urllib.parse.quote_plus(role_data_str, safe='')

# ---- Step 6: Build formIdValueData ----
sys.stderr.write('Building formIdValueData...\n')
form_id_value = {}
for item in enc_data:
    fid = str(item['id'])
    entry = {}
    for k in ('compt', 'groupValues', 'inDetailGroupIndex', 'id', 'hasAuthority', 'isShow'):
        if k in item:
            entry[k] = item[k]
    if 'hasAuthority' not in entry:
        entry['hasAuthority'] = True
    if 'inDetailGroupIndex' not in entry:
        entry['inDetailGroupIndex'] = -1
    if 'groupValues' not in entry or not entry['groupValues']:
        entry['groupValues'] = [{'values': [[{'val': ''}]], 'isShow': True}]
    form_id_value[fid] = entry

set_values(form_id_value, 1, contact_value)
for fid, cid in [(2, '2'), (3, '3'), (4, '4'), (5, '5'), (6, '6'), (7, '7'), (8, '8')]:
    set_values(form_id_value, fid, {'val': user_info.get(cid, '')})
set_values(form_id_value, 10, {'val': cancel_time})
set_values(form_id_value, 11, {'val': '否', 'score': 0, 'valShow': '否'})
set_values(form_id_value, 12, {'val': qjbh})
set_values(form_id_value, 13, {'val': status_val})
set_values(form_id_value, 14, location)

fvd_encoded = encode_fvd(form_id_value)
fvd_enc = urllib.parse.quote_plus(fvd_encoded, safe='')
sys.stderr.write(f'formIdValueData compressed: {len(fvd_encoded)} chars\n')

# ---- Step 7: Build save body ----
save_body = (
    f'formId={form_id}'
    f'&aprvAppId={aprv_app_id}'
    f'&formData='
    f'&version={version}'
    f'&cdtnIdStr={cdtn_id_str}'
    f'&ext='
    f'&fidEnc={fid_enc}'
    f'&organizeData={org_enc}'
    f'&roleData={role_enc}'
    f'&uuid={page_uuid}'
    f'&approveFlowUserList={afl_enc}'
    f'&state={state}'
    f'&userDeptJson={udj_enc}'
    f'&comptMatchingJson={compt_enc}'
    f'&processLeaveId=0'
    f'&uniqueCondition=%5B%5D'
    f'&submitVersion={updatetime}'
    f'&isApprvDeleted=false'
    f'&approveLaunchUserId='
    f'&formIdValueData={fvd_enc}'
    f'&checkCode='
    f'&oaUidEnc={urllib.parse.quote_plus(oa_uid_enc, safe="")}'
)

sys.stderr.write(f'save_body length={len(save_body)}\n')
print(save_body)
PYEOF
)

if [ -z "$SAVE_BODY" ]; then
    log "❌ 构建提交数据失败"
    exit 1
fi

# =============================================
# Submit cancel form
# =============================================
log "提交销假表单..."

SAVE_TMP=$(mktemp)
printf '%s' "$SAVE_BODY" > "$SAVE_TMP"

SAVE_RESP=$(curl -s --compressed -w "\n%{http_code}" -X POST \
  "${BASE_URL}/data/approve/apps/forms/fore/user/save" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -H "$ACCEPT_JSON" \
  -H "User-Agent: $UA" \
  -H "Origin: ${BASE_URL}" \
  -H "Referer: ${BASE_URL}/apps/forms/mobile/apply.html?formType=1&formid=${FORM_ID}&aprvAppId=${APRV_APP_ID}&uuid=${UUID}&pageEnc=${PAGE_ENC}&state=${STATE}&fidEnc=${FID_ENC}" \
  -b "$COOKIES" \
  -d "@$SAVE_TMP" 2>&1)

rm -f "$SAVE_TMP"

SAVE_CODE=$(echo "$SAVE_RESP" | tail -1)
SAVE_BODY_RESP=$(echo "$SAVE_RESP" | head -c 2000)

log "提交 HTTP $SAVE_CODE"
log "响应: $SAVE_BODY_RESP"

if echo "$SAVE_BODY_RESP" | grep -qE '"success":true'; then
  log "✅ 销假提交成功！"
  APRVID=$(echo "$SAVE_BODY_RESP" | grep -oE '"aprvId":[0-9]+' | head -1 | cut -d: -f2)
  [ -n "$APRVID" ] && log "审批ID: $APRVID"
elif echo "$SAVE_BODY_RESP" | grep -qE '"success":false'; then
  log "❌ 销假提交失败，请检查日志"
  log "完整响应: $(echo "$SAVE_RESP" | head -c 5000)"
  exit 1
else
  log "⚠️  无法判断结果 (HTTP $SAVE_CODE)"
  log "完整响应: $(echo "$SAVE_RESP" | head -c 5000)"
  exit 2
fi

log "========== 执行完成 =========="
