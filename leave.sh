#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
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
FORM_ID=82987
APRV_APP_ID=82987
STATE=214456
FID_ENC="f03d643e10dbcc06"
PAGE_ENC="653d98fb25cfc04e22785a48b9b1765b"
BASE_URL="https://office.chaoxing.com"

UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36"
ACCEPT_JSON="Accept: application/json, text/plain, */*"

# =============================================
# 0. Cookie & UUID
# =============================================
if [ -n "$CHAOXING_COOKIES" ]; then
    COOKIES="$CHAOXING_COOKIES"
else
    COOKIES=$(cat "$SCRIPT_DIR/cookies")
fi

UUID=$($PYTHON -c "import uuid; print(uuid.uuid4().hex)")
log "========== 开始执行请假提交 =========="
log "UUID: $UUID"

# =============================================
# 1. Calculate dates
# =============================================
CALC=$($PYTHON -c "
from datetime import date, datetime, timedelta
today = date.today()
days_until_thu = (3 - today.weekday()) % 7
if days_until_thu == 0 and datetime.now().hour >= 18:
    days_until_thu = 7
thu = today + timedelta(days=days_until_thu)
fri = thu + timedelta(days=1)
sun = thu + timedelta(days=3)
start = fri.isoformat() + ' 12:00'
end   = sun.isoformat() + ' 18:00'
apply = thu.isoformat()
duration = str(round(54/24, 1))
print(f'{start}|{end}|{apply}|{duration}')
")

IFS='|' read START_TIME END_TIME APPLY_DATE DURATION <<< "$CALC"

log "请假开始: $START_TIME"
log "请假结束: $END_TIME"
log "申请日期: $APPLY_DATE"
log "请假时长: $DURATION 天"

# =============================================
# 2. Python: all API calls + build save body
# =============================================
log "开始构建提交数据..."

SAVE_BODY=$(START_TIME="$START_TIME" END_TIME="$END_TIME" APPLY_DATE="$APPLY_DATE" \
    DURATION="$DURATION" FORM_ID="$FORM_ID" APRV_APP_ID="$APRV_APP_ID" \
    STATE="$STATE" FID_ENC="$FID_ENC" PAGE_ENC="$PAGE_ENC" UUID="$UUID" \
    BASE_URL="$BASE_URL" COOKIES="$COOKIES" \
    UA="$UA" ACCEPT_JSON="$ACCEPT_JSON" SCRIPT_DIR="$SCRIPT_DIR" LEAVE_PHOTO_URL="$LEAVE_PHOTO_URL" \
    $PYTHON << 'PYEOF'
import json, sys, time, urllib.parse, uuid as _uuid, subprocess, tempfile as _tmp, os, base64, zlib, hashlib, random
from datetime import date, datetime, timedelta

# ---- Config from env ----
start_time = os.environ['START_TIME']
end_time = os.environ['END_TIME']
apply_date = os.environ['APPLY_DATE']
duration = os.environ['DURATION']
form_id = os.environ['FORM_ID']
aprv_app_id = os.environ['APRV_APP_ID']
state = os.environ['STATE']
fid_enc = os.environ['FID_ENC']
page_enc = os.environ['PAGE_ENC']
page_uuid = os.environ['UUID']
base_url = os.environ['BASE_URL']
cookies = os.environ['COOKIES']
ua = os.environ['UA']
accept_json = os.environ['ACCEPT_JSON']
script_dir = os.environ.get('SCRIPT_DIR', '')
leave_photo_url = os.environ.get('LEAVE_PHOTO_URL', '')

web_apply_url = (
    f'{base_url}/apps/forms/web/apply.html?formType=1&formType=1&edit=0&backurl='
    f'&roleId=&aprvId=0&uuid={page_uuid}&desensitization='
    f'&pageEnc={page_enc}'
)

def get_cookie(name):
    for part in cookies.split(';'):
        part = part.strip()
        if '=' not in part:
            continue
        k, v = part.split('=', 1)
        if k.strip() == name:
            return urllib.parse.unquote(v.strip())
    return ''

def resolve_uid_uname():
    uid_raw = os.environ.get('CX_UID') or get_cookie('oa_uid') or get_cookie('_uid') or get_cookie('UID')
    uname = os.environ.get('CX_NAME') or get_cookie('oa_name') or get_cookie('uname') or '姓名'
    try:
        uid_val = int(uid_raw)
    except Exception:
        raise RuntimeError('缺少用户 UID：请设置 CX_UID，或确保 Cookie 中包含 oa_uid/_uid/UID')
    return uid_val, uname

def curl_get(url, referer=None):
    cmd = ['curl', '-s', '--compressed', '-w', '\n%{http_code}', '-X', 'GET', url,
           '-H', accept_json, '-H', f'User-Agent: {ua}',
           '-H', f'Origin: {base_url}',
           '-H', f'Cookie: {cookies}']
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
           '-H', f'Origin: {base_url}',
           '-H', f'Cookie: {cookies}']
    if referer:
        cmd.extend(['-H', f'Referer: {referer}'])
    cmd.extend(['-d', '@'+data_file.name])
    result = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8', errors='replace')
    os.unlink(data_file.name)
    lines = result.stdout.strip().split('\n')
    code = lines[-1] if lines else '0'
    body = '\n'.join(lines[:-1]) if len(lines) > 1 else ''
    return code, body

# ---- Step 0: Get oaUidEnc from cookie/userinfo API ----
sys.stderr.write('Getting oaUidEnc...\n')
code, body = curl_get(f'{base_url}/data/common/cookie/userinfo', base_url + '/')
ui_data = json.loads(body)
oa_uid_enc = ''
if ui_data.get('success'):
    key = base64.b64decode('anZHRFg2ekNaVmliZmExTA==')
    from Crypto.Cipher import AES
    from Crypto.Util.Padding import unpad
    cipher = AES.new(key, AES.MODE_ECB)
    decrypted = unpad(cipher.decrypt(base64.b64decode(ui_data['data'])), AES.block_size)
    cookie_info = json.loads(decrypted)
    oa_uid_enc = cookie_info.get('oaCookieUserInfo', {}).get('oaUidEnc', '')
    sys.stderr.write(f'oaUidEnc={oa_uid_enc[:30]}...\n')
else:
    sys.stderr.write(f'cookie/userinfo failed: {body[:200]}\n')

# ---- Step 1: Load web apply page ----
sys.stderr.write('Loading apply page...\n')
code, _ = curl_get(web_apply_url, base_url + '/')
sys.stderr.write(f'Page HTTP {code}\n')

# ---- Step 2: verify/info ----
sys.stderr.write('Getting form structure...\n')
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

alias_to_id = {}
for item in enc_data:
    alias_to_id[item.get('alias', '')] = str(item['id'])

# ---- Step 3: Get signature ----
sys.stderr.write('Getting signature...\n')
code, body = curl_get(f'{base_url}/front/sign/find/user/signature?signType=1', web_apply_url)
sign_data = json.loads(body)
sign_raw = sign_data.get('data', {}).get('sign', '{}')
if isinstance(sign_raw, str):
    sign_info = json.loads(sign_raw)
else:
    sign_info = sign_raw
signature_url = sign_info.get('signature', '')
sys.stderr.write(f'Signature URL: {signature_url[:60]}...\n')

# ---- Step 4: Get user info from requesturl ----
sys.stderr.write('Getting user info...\n')
requesturl_body = (
    'url=8rC0Ynnzf3EAu5NbMBaFiA%3D%3D'
    '&response=%5B%7B%22compt%22%3A%22editinput%22%2C%22jpath%22%3A%22%24.xh%22%2C%22pcid%22%3A0%2C%22label%22%3A%22%E5%AD%A6%E5%8F%B7%22%2C%22cid%22%3A2%7D%2C%7B%22compt%22%3A%22editinput%22%2C%22jpath%22%3A%22%24.sznj%22%2C%22pcid%22%3A0%2C%22label%22%3A%22%E5%B9%B4%E7%BA%A7%22%2C%22cid%22%3A3%7D%2C%7B%22compt%22%3A%22editinput%22%2C%22jpath%22%3A%22%24.yx%22%2C%22pcid%22%3A0%2C%22label%22%3A%22%E9%99%A2%E7%B3%BB%22%2C%22cid%22%3A4%7D%2C%7B%22compt%22%3A%22editinput%22%2C%22jpath%22%3A%22%24.zy%22%2C%22pcid%22%3A0%2C%22label%22%3A%22%E4%B8%93%E4%B8%9A%22%2C%22cid%22%3A5%7D%2C%7B%22compt%22%3A%22editinput%22%2C%22jpath%22%3A%22%24.bj%22%2C%22pcid%22%3A0%2C%22label%22%3A%22%E7%8F%AD%E7%BA%A7%22%2C%22cid%22%3A6%7D%2C%7B%22compt%22%3A%22editinput%22%2C%22jpath%22%3A%22%24.fdyList%5B0%5D.fdyxm%22%2C%22pcid%22%3A0%2C%22label%22%3A%22%E8%BE%85%E5%AF%BC%E5%91%98%E5%A7%93%E5%90%8D%22%2C%22cid%22%3A7%7D%2C%7B%22compt%22%3A%22editinput%22%2C%22jpath%22%3A%22%24.fdyList%5B0%5D.fdygh%22%2C%22pcid%22%3A0%2C%22label%22%3A%22%E8%BE%85%E5%AF%BC%E5%91%98%E5%B7%A5%E5%8F%B7%22%2C%22cid%22%3A8%7D%5D'
    '&template=00f6d40d58979cba877c06889691bf6502740ffffae7fd8177bff41cf59ca673ef5d34f5042f8a7e8ef2e5622e98c23c95909ff50bb9cce63993492ba229fcdd38685448658e83d04970df6a28fd2fb886c301d1df58a6bbbae8d45b98e5be7b'
    '&id=46061'
    '&urlHeaders=c12642b70ea70fc05b93b1925f7bf6fc'
    '&contactMultipleConfig=%7B%7D'
)
code, body = curl_post(f'{base_url}/front/open/share/apps/forms/fore/events/requesturl', requesturl_body, web_apply_url)
requesturl_data = json.loads(body)
user_info = {}
if requesturl_data.get('success'):
    for item in requesturl_data.get('data', []):
        cid = str(item.get('cid', ''))
        val = item.get('val', '')
        user_info[cid] = val
    sys.stderr.write(f'User info: xh={user_info.get("2","")}, yx={user_info.get("4","")}, bj={user_info.get("6","")}\n')
else:
    sys.stderr.write(f'requesturl failed: {body[:200]}\n')

# ---- Step 5: Build formUserData for approvers call ----
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

for item in form_user_data:
    alias = item.get('alias', '')
    fs = item.get('fields', [])
    if not fs:
        continue
    if alias == 'qjkssj':
        fs[0]['values'][0]['val'] = start_time
    elif alias == 'qjjssj':
        fs[0]['values'][0]['val'] = end_time
    elif alias == 'qjsqsj':
        fs[0]['values'][0]['val'] = apply_date
    elif alias == 'qjsc':
        fs[0]['values'][0]['val'] = duration

fud_json = json.dumps(form_user_data, ensure_ascii=False, separators=(',', ':'))
fud_enc = urllib.parse.quote_plus(fud_json, safe='')
uid, uname = resolve_uid_uname()
compt_json = json.dumps({'contact1': {'name': '姓名', 'value': uid}}, ensure_ascii=False, separators=(',', ':'))
compt_enc = urllib.parse.quote_plus(compt_json, safe='')

# ---- Step 6: Call approvers API ----
sys.stderr.write('Calling approvers...\n')
apprv_body = (
    f'state={state}&formId={form_id}&formType=approveForm&aprvAppId={aprv_app_id}'
    f'&formUserId=0&fidEnc={fid_enc}&aprvTypeId=10000'
    f'&organizeId=0&regionOrganizeId=0&roleId=0&loadAprvUserCount=2'
    f'&formUserData={fud_enc}&comptMatchingJson={compt_enc}'
    f'&pageEnc={page_enc}&formData=&approveLaunchUserId='
)
code, body = curl_post(f'{base_url}/data/approve/apps/forms/fore/list/approvers', apprv_body, web_apply_url)
apprv_resp = json.loads(body)
apprv_data = apprv_resp.get('data', {})
sys.stderr.write(f'approvers success={apprv_resp.get("success")}\n')

# userList, userDeptJson are JSON STRINGS from the API - use directly
user_list_str = apprv_data.get('userList', '[]')
user_dept_json_str = apprv_data.get('userDeptJson', '{}')
condition_id_list = apprv_data.get('conditionIdList', [])
role_list = apprv_data.get('roleList', [])
last_organize_str = apprv_data.get('lastOrganize', '{}')

role_data_str = json.dumps(role_list[0], ensure_ascii=False, separators=(',', ':')) if role_list else '{"roleId":0,"roleName":"","show":false}'
cdtn_id_str = ','.join(str(c) for c in condition_id_list) if condition_id_list else ''

# URL-encode JSON strings
udj_enc = urllib.parse.quote_plus(user_dept_json_str, safe='')
afl_enc = urllib.parse.quote_plus(user_list_str, safe='')
org_enc = urllib.parse.quote_plus('[{"organizeId":0,"organizeName":"","show":false,"type":0},{"organizeId":0,"organizeName":"","show":false,"type":1}]', safe='')
role_enc = urllib.parse.quote_plus(role_data_str, safe='')

# ---- Step 7: Build formIdValueData for save ----
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

# Fill date values
for alias, val in [('qjsqsj', apply_date), ('qjkssj', start_time), ('qjjssj', end_time)]:
    fid = alias_to_id.get(alias)
    if fid and fid in form_id_value:
        gv = form_id_value[fid].get('groupValues', [])
        if gv and gv[0].get('values') and gv[0]['values'][0]:
            gv[0]['values'][0][0]['val'] = val

# Fill contact field with oaUidEnc
contact_fid = alias_to_id.get('xm', '1')
if contact_fid in form_id_value:
    gv = form_id_value[contact_fid].get('groupValues', [])
    if gv and gv[0].get('values') and gv[0]['values'][0] is not None:
        if not gv[0]['values'][0]:
            gv[0]['values'][0] = [{}]
        gv[0]['values'][0][0] = {
            'puid': uid,
            'uname': uname,
            'uidEnc': oa_uid_enc
        }

# Fill duration
fid = alias_to_id.get('qjsc')
if fid and fid in form_id_value:
    gv = form_id_value[fid].get('groupValues', [])
    if gv and gv[0].get('values') and gv[0]['values'][0]:
        gv[0]['values'][0][0]['val'] = duration

# Fill signature (field 25)
if '25' in form_id_value and signature_url:
    form_id_value['25']['groupValues'] = [{'values': [[{'val': signature_url}]], 'isShow': True}]

# Fill file upload (field 26) - use photo URL from environment
if '26' in form_id_value:
    if leave_photo_url:
        file_name = leave_photo_url.split('?')[0].rstrip('/').split('/')[-1] or 'leave-photo.jpg'
        suffix = file_name.rsplit('.', 1)[-1].lower() if '.' in file_name else 'jpg'
        form_id_value['26']['groupValues'] = [{'values': [[{
            'modifyDate': int(time.time() * 1000),
            'name': file_name,
            'objectId': '',
            'size': '',
            'thumbnail': leave_photo_url,
            'suffix': suffix,
            'preview': leave_photo_url,
            'previewUrl': leave_photo_url,
            'isfile': True,
            'isImg': suffix in ('jpg', 'jpeg', 'png', 'gif', 'bmp'),
            'isOffice': False,
            'isMirror': False,
            'filetype': '',
            'filepath': '',
            'sort': 0,
            'topsort': 0,
            'resTypeValue': 3,
            'extinfo': ''
        }]], 'isShow': True}]
    else:
        form_id_value['26']['groupValues'] = [{'values': [[]], 'isShow': True}]

# Fill user info fields from requesturl
user_info_map = {
    'xh': '2', 'sznj': '3', 'yx': '4', 'zy': '5',
    'bj': '6', 'fdyxm': '7', 'fdygh': '8'
}
for alias, cid in user_info_map.items():
    fid = alias_to_id.get(alias)
    val = user_info.get(cid, '')
    if fid and fid in form_id_value and val:
        gv = form_id_value[fid].get('groupValues', [])
        if gv and gv[0].get('values') and gv[0]['values'][0]:
            gv[0]['values'][0][0]['val'] = val

# Fill leave type (qjlx) - selectbox
fid = alias_to_id.get('qjlx')
if fid and fid in form_id_value:
    gv = form_id_value[fid].get('groupValues', [])
    if gv and gv[0].get('values') and gv[0]['values'][0]:
        gv[0]['values'][0][0] = {'val': '事假', 'className': '', 'color': '', 'score': 0, 'valShow': '事假'}

# Fill radiobuttons: 是否省外→否
for alias in ('sfcsheng',):
    fid = alias_to_id.get(alias)
    if fid and fid in form_id_value:
        gv = form_id_value[fid].get('groupValues', [])
        if gv and gv[0].get('values') and gv[0]['values'][0]:
            gv[0]['values'][0][0] = {'val': '否', 'isOther': False, 'score': 0}

# Fill radiobuttons: 是否出校→是, 是否出市→是
for alias in ('sfcx', 'sfcshi'):
    fid = alias_to_id.get(alias)
    if fid and fid in form_id_value:
        gv = form_id_value[fid].get('groupValues', [])
        if gv and gv[0].get('values') and gv[0]['values'][0]:
            gv[0]['values'][0][0] = {'val': '是', 'isOther': False, 'score': 0}

# Fill 联系方式 (id=23, no alias)
if '23' in form_id_value:
    gv = form_id_value['23'].get('groupValues', [])
    if gv and gv[0].get('values') and gv[0]['values'][0]:
        gv[0]['values'][0][0]['val'] = '1012'

# Compress formIdValueData
def encode_fvd(data):
    json_str = json.dumps(data, ensure_ascii=False, separators=(',', ':'))
    zlib_bytes = zlib.compress(json_str.encode('utf-8'))
    xored = bytes([b ^ 102 for b in zlib_bytes])
    binary_str = ''.join(chr(b) for b in xored)
    return base64.b64encode(binary_str.encode('latin-1')).decode('ascii')

fvd_encoded = encode_fvd(form_id_value)
sys.stderr.write(f'formIdValueData compressed: {len(fvd_encoded)} chars\n')
fvd_enc = urllib.parse.quote_plus(fvd_encoded, safe='')

# ---- Step 8: Build save body ----
save_body = (
    f'formId={form_id}'
    f'&aprvAppId={aprv_app_id}'
    f'&uniqueCondition=%5B%5D'
    f'&version={version}'
    f'&approveFlowUserList={afl_enc}'
    f'&cdtnIdStr={cdtn_id_str}'
    f'&fidEnc={fid_enc}'
    f'&processLeaveId=0'
    f'&organizeData={org_enc}'
    f'&roleData={role_enc}'
    f'&uuid={page_uuid}'
    f'&state={state}'
    f'&userDeptJson={udj_enc}'
    f'&comptMatchingJson={compt_enc}'
    f'&submitVersion={updatetime}'
    f'&isApprvDeleted=false'
    f'&formIdValueData={fvd_enc}'
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
# 3. Submit leave form
# =============================================
log "提交请假表单..."

SAVE_TMP=$(mktemp)
echo "$SAVE_BODY" > "$SAVE_TMP"

SAVE_RESP=$(curl -s --compressed -w "\n%{http_code}" -X POST \
  "${BASE_URL}/data/approve/apps/forms/fore/user/save" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -H "$ACCEPT_JSON" \
  -H "User-Agent: $UA" \
  -H "Origin: ${BASE_URL}" \
  -H "Referer: ${BASE_URL}/apps/forms/web/apply.html?formType=1&formType=1&edit=0&backurl=&roleId=&aprvId=0&uuid=${UUID}&desensitization=&pageEnc=${PAGE_ENC}" \
  -b "$COOKIES" \
  -d "@$SAVE_TMP" 2>&1)

rm -f "$SAVE_TMP"

SAVE_CODE=$(echo "$SAVE_RESP" | tail -1)
SAVE_BODY_RESP=$(echo "$SAVE_RESP" | head -c 2000)

log "提交 HTTP $SAVE_CODE"
log "响应: $SAVE_BODY_RESP"

# =============================================
# 4. Check result
# =============================================
if echo "$SAVE_BODY_RESP" | grep -qE '"success":true'; then
  log "✅ 请假提交成功！"
  # Extract aprvId if present
  APRVID=$(echo "$SAVE_BODY_RESP" | grep -oE '"aprvId":[0-9]+' | head -1 | cut -d: -f2)
  [ -n "$APRVID" ] && log "审批ID: $APRVID"
elif echo "$SAVE_BODY_RESP" | grep -qE '"success":false'; then
  log "❌ 请假提交失败，请检查日志"
  log "完整响应: $(echo "$SAVE_RESP" | head -c 5000)"
  exit 1
else
  log "⚠️  无法判断结果 (HTTP $SAVE_CODE)"
  log "完整响应: $(echo "$SAVE_RESP" | head -c 5000)"
  exit 2
fi

log "========== 执行完成 =========="
