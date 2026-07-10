// ===== 模拟用户数据 =====
const currentUser = {
  name: '',
  avatar: 'https://photo.chaoxing.com/p/323291431_50',
  sno: '',
  grade: '',
  dept: '',
  major: '',
  className: '',
  counselorName: '',
  counselorId: '',
  counselorAvatar: 'https://photo.chaoxing.com/p/306359839_50'
};

// ===== 表单缓存（不缓存时间/日期） =====
const FORM_CACHE_KEY = 'leaveFormDraft:v1';
const FORM_CACHE_FIELDS = [
  'studentNameInput',
  'studentIdInput',
  'gradeInput',
  'deptInput',
  'majorInput',
  'classNameInput',
  'dormInput',
  'counselorNameInput',
  'counselorIdInput',
  'leaveTypeSelect',
  'leaveCampusSelect',
  'leaveCitySelect',
  'leaveProvinceSelect'
];
const DEFAULT_FACE_PHOTO_URL = '';
const DEFAULT_SIGNATURE_URL = '';
const MAX_CACHE_IMAGE_EDGE = 1280;
const MAX_CACHE_DATA_URL_LENGTH = 3 * 1024 * 1024;

// ===== 变量声明 =====
let facePhotoFile = null;
let signatureData = null;

// ===== 初始化 =====
let facePhotoDataUrl = DEFAULT_FACE_PHOTO_URL;
let signatureDataUrl = DEFAULT_SIGNATURE_URL;

(function init() {
  // 公开仓库不预置面部照片和签名图片
  facePhotoFile = null;
  clearFacePhotoUi();
  clearSignatureUi();

  // 设置默认申请日期（昨天）
  const now = new Date();
  const yesterday = new Date(now);
  yesterday.setDate(yesterday.getDate() - 1);
  const yesterdayStr = yesterday.toISOString().split('T')[0];
  document.getElementById('applyDateInput').value = yesterdayStr;
  document.getElementById('applyDateDispText').textContent = yesterdayStr;

  // 设置默认开始/结束时间（今天12:00到18:00）
  const todayStr = now.toISOString().split('T')[0];
  const startStr = todayStr + 'T12:00';
  const endStr   = todayStr + 'T18:00';
  document.getElementById('startTimeInput').value = startStr;
  document.getElementById('endTimeInput').value = endStr;
  document.getElementById('startTimeDispText').textContent = startStr.replace('T',' ');
  document.getElementById('endTimeDispText').textContent = endStr.replace('T',' ');
  calcDuration();
  loadFormCache();
  bindFormCache();
})();

// ===== 表单缓存 =====
function readFormCache() {
  try {
    var raw = localStorage.getItem(FORM_CACHE_KEY);
    return raw ? JSON.parse(raw) : null;
  } catch (e) {
    return null;
  }
}

function loadFormCache() {
  var cache = readFormCache();
  if (!cache) return;
  FORM_CACHE_FIELDS.forEach(function(id) {
    var el = document.getElementById(id);
    if (!el || cache[id] === undefined) return;
    el.value = cache[id];
  });
  syncName(document.getElementById('studentNameInput').value);
  syncHeaderInfo();
  syncCounselorName(document.getElementById('counselorNameInput').value);
  syncCachedSelectDisplay();
  if (Object.prototype.hasOwnProperty.call(cache, 'facePhoto')) {
    if (cache.facePhoto && cache.facePhoto.dataUrl) applyFacePhotoCache(cache.facePhoto);
    else if (cache.facePhoto === null) clearFacePhotoUi();
  }
  if (Object.prototype.hasOwnProperty.call(cache, 'signature')) {
    if (cache.signature && cache.signature.dataUrl) applySignatureCache(cache.signature);
    else if (cache.signature === null) clearSignatureUi();
  }
}

function bindFormCache() {
  FORM_CACHE_FIELDS.forEach(function(id) {
    var el = document.getElementById(id);
    if (!el) return;
    el.addEventListener('input', saveFormCache);
    el.addEventListener('change', saveFormCache);
  });
}

function saveFormCache(showError) {
  var cache = {};
  FORM_CACHE_FIELDS.forEach(function(id) {
    var el = document.getElementById(id);
    if (el) cache[id] = el.value;
  });
  if (facePhotoDataUrl === null) {
    cache.facePhoto = null;
  } else if (facePhotoDataUrl && facePhotoDataUrl !== DEFAULT_FACE_PHOTO_URL) {
    if (facePhotoDataUrl.length <= MAX_CACHE_DATA_URL_LENGTH) {
      cache.facePhoto = {
        name: facePhotoFile && facePhotoFile.name ? facePhotoFile.name : 'photo.jpg',
        type: facePhotoFile && facePhotoFile.type ? facePhotoFile.type : 'image/jpeg',
        size: facePhotoFile && facePhotoFile.size ? facePhotoFile.size : 0,
        dataUrl: facePhotoDataUrl
      };
    } else if (showError === true) {
      showToast('图片较大，无法缓存到本地');
    }
  }
  if (signatureDataUrl === null) {
    cache.signature = null;
  } else if (signatureDataUrl && signatureDataUrl !== DEFAULT_SIGNATURE_URL) {
    cache.signature = { dataUrl: signatureDataUrl };
  }
  try {
    localStorage.setItem(FORM_CACHE_KEY, JSON.stringify(cache));
  } catch (e) {
    if (cache.facePhoto) {
      delete cache.facePhoto;
      try {
        localStorage.setItem(FORM_CACHE_KEY, JSON.stringify(cache));
      } catch (err) {}
    }
    if (showError === true) showToast('缓存空间不足，图片未缓存');
  }
}

function syncCachedSelectDisplay() {
  document.getElementById('leaveTypeDispText').textContent = document.getElementById('leaveTypeSelect').value;
  document.getElementById('leaveTypeDispText2').textContent = document.getElementById('leaveTypeSelect').value;
  document.getElementById('leaveCampusDispText').textContent = document.getElementById('leaveCampusSelect').value;
  document.getElementById('leaveCityDispText').textContent = document.getElementById('leaveCitySelect').value;
  document.getElementById('leaveProvinceDispText').textContent = document.getElementById('leaveProvinceSelect').value;
}

function applyFacePhotoCache(photo) {
  facePhotoFile = {
    name: photo.name || 'photo.jpg',
    type: photo.type || 'image/jpeg',
    size: photo.size || 0
  };
  facePhotoDataUrl = photo.dataUrl;
  document.getElementById('faceFileName').textContent = facePhotoFile.name;
  document.getElementById('faceFileSize').textContent = facePhotoFile.size ? (facePhotoFile.size / 1024).toFixed(2) + 'KB' : '--';
  document.getElementById('faceFileItem').style.display = '';
  var icon = document.getElementById('faceFileItem').querySelector('.upload_file_icon');
  icon.src = facePhotoDataUrl;
  icon.style.borderRadius = '4px';
}

function clearFacePhotoUi() {
  facePhotoFile = null;
  facePhotoDataUrl = null;
  document.getElementById('faceFileName').textContent = '';
  document.getElementById('faceFileSize').textContent = '';
  document.getElementById('faceFileItem').style.display = 'none';
}

function applySignatureCache(signature) {
  signatureData = signature.dataUrl;
  signatureDataUrl = signature.dataUrl;
  document.getElementById('signatureEditImg').src = signatureDataUrl;
  document.getElementById('signatureAutograph').style.display = '';
  var ph = document.getElementById('signaturePlaceholderDiv');
  if (ph) ph.style.display = 'none';
}

function clearSignatureUi() {
  signatureData = null;
  signatureDataUrl = null;
  document.getElementById('signatureEditImg').src = '';
  document.getElementById('signatureAutograph').style.display = 'none';
  showSignaturePlaceholder();
}

function showSignaturePlaceholder() {
  if (!document.getElementById('signaturePlaceholderDiv')) {
    var ph = document.createElement('div');
    ph.id = 'signaturePlaceholderDiv';
    ph.style.cssText = 'border:1px dashed #dedfe0;border-radius:5px;padding:20px;text-align:center;min-height:80px;display:flex;align-items:center;justify-content:center;cursor:pointer;';
    ph.innerHTML = '<span style="color:#c0c0c3;font-size:14px;">点击进行手写签名</span>';
    ph.onclick = openSignaturePad;
    document.getElementById('signatureEdit').appendChild(ph);
  } else {
    document.getElementById('signaturePlaceholderDiv').style.display = '';
  }
}

function compressImageForCache(dataUrl, callback) {
  var img = new Image();
  img.onload = function() {
    var longest = Math.max(img.width, img.height);
    if (!longest || (longest <= MAX_CACHE_IMAGE_EDGE && dataUrl.length <= MAX_CACHE_DATA_URL_LENGTH)) {
      callback(dataUrl);
      return;
    }
    var scale = Math.min(1, MAX_CACHE_IMAGE_EDGE / longest);
    var canvas = document.createElement('canvas');
    canvas.width = Math.max(1, Math.round(img.width * scale));
    canvas.height = Math.max(1, Math.round(img.height * scale));
    var ctx = canvas.getContext('2d');
    ctx.fillStyle = '#fff';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
    callback(canvas.toDataURL('image/jpeg', 0.82));
  };
  img.onerror = function() { callback(dataUrl); };
  img.src = dataUrl;
}

// ===== 显示/隐藏编辑控件 =====
function showEditMode() {
  var formDetail = document.getElementById('forms-detail');
  if (formDetail) formDetail.classList.add('form-detail--footer-space');

  // 宿舍号
  document.getElementById('dormDisplay').style.display = 'none';
  document.getElementById('dormInput').style.display = '';
  // 请假类型
  document.getElementById('leaveTypeDisplay').style.display = 'none';
  document.getElementById('leaveTypeDetailDisplay').style.display = 'none';
  document.getElementById('leaveTypeEdit').style.display = '';
  // 是否出校/市/省
  document.getElementById('leaveCampusDisplay').style.display = 'none';
  document.getElementById('leaveCampusEdit').style.display = '';
  document.getElementById('leaveCityDisplay').style.display = 'none';
  document.getElementById('leaveCityEdit').style.display = '';
  document.getElementById('leaveProvinceDisplay').style.display = 'none';
  document.getElementById('leaveProvinceEdit').style.display = '';
  // 时间
  document.getElementById('startTimeDisplay').style.display = 'none';
  document.getElementById('startTimeInput').style.display = '';
  document.getElementById('endTimeDisplay').style.display = 'none';
  document.getElementById('endTimeInput').style.display = '';
  // 申请时间
  document.getElementById('applyDateDisplay').style.display = 'none';
  document.getElementById('applyDateInput').style.display = '';
}
showEditMode();

// ===== 面部照片上传 =====
function handleFacePhoto(files) {
  if (!files || !files[0]) return;
  const file = files[0];
  if (!file.type.startsWith('image/')) { showToast('请选择图片文件'); return; }
  if (file.size > 10 * 1024 * 1024) { showToast('图片不超过10MB'); return; }
  facePhotoFile = file;
  const reader = new FileReader();
  reader.onload = function(e) {
    compressImageForCache(e.target.result, function(cachedDataUrl) {
      facePhotoDataUrl = cachedDataUrl;
      document.getElementById('faceFileName').textContent = file.name;
      document.getElementById('faceFileSize').textContent = (file.size/1024).toFixed(2)+'KB';
      document.getElementById('faceFileItem').style.display = '';
      document.getElementById('faceFileItem').querySelector('.upload_file_icon').src = facePhotoDataUrl;
      document.getElementById('faceFileItem').querySelector('.upload_file_icon').style.borderRadius = '4px';
      saveFormCache(true);
    });
  };
  reader.readAsDataURL(file);
}
function removeFacePhoto() {
  clearFacePhotoUi();
  saveFormCache();
}

// ===== 时长计算 =====
function calcDuration() {
  const start = document.getElementById('startTimeInput').value;
  const end = document.getElementById('endTimeInput').value;
  if (!start || !end) { document.getElementById('durationDisplay').textContent = '0'; return; }
  const diffMs = new Date(end) - new Date(start);
  if (diffMs <= 0) { document.getElementById('durationDisplay').textContent = '时间错误'; return; }
  const days = diffMs / (1000 * 60 * 60 * 24);
  document.getElementById('durationDisplay').textContent = days.toFixed(1);
}

// ===== 签名 =====
function openSignaturePad() {
  const canvas = document.createElement('canvas');
  canvas.width = 300; canvas.height = 150;
  canvas.style.cssText = 'border:1px solid #dedfe0;border-radius:5px;cursor:crosshair;';
  const popup = document.createElement('div');
  popup.style.cssText = 'position:fixed;top:0;left:0;right:0;bottom:0;background:rgba(0,0,0,.5);z-index:9999;display:flex;flex-direction:column;align-items:center;justify-content:center;';
  popup.innerHTML = '<div style="background:#fff;border-radius:8px;padding:20px;text-align:center;"><div style="font-size:16px;font-weight:600;margin-bottom:12px;">手写签名</div><div id="canvasContainer"></div><div style="margin-top:12px;display:flex;gap:10px;justify-content:center;"><button id="clearBtn" style="padding:8px 24px;border:1px solid #dedfe0;border-radius:20px;background:#fff;cursor:pointer;font-size:14px;">重写</button><button id="confirmBtn" style="padding:8px 24px;border:none;border-radius:20px;background:#006ce2;color:#fff;cursor:pointer;font-size:14px;">确定</button></div></div>';
  document.body.appendChild(popup);
  document.getElementById('canvasContainer').appendChild(canvas);
  const ctx = canvas.getContext('2d');
  ctx.strokeStyle = '#000'; ctx.lineWidth = 2; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
  let drawing = false;
  function getPos(e) {
    const rect = canvas.getBoundingClientRect();
    return { x: (e.touches ? e.touches[0].clientX : e.clientX) - rect.left, y: (e.touches ? e.touches[0].clientY : e.clientY) - rect.top };
  }
  canvas.addEventListener('mousedown', e => { drawing = true; const p = getPos(e); ctx.beginPath(); ctx.moveTo(p.x, p.y); });
  canvas.addEventListener('mousemove', e => { if (!drawing) return; const p = getPos(e); ctx.lineTo(p.x, p.y); ctx.stroke(); });
  canvas.addEventListener('mouseup', () => { drawing = false; });
  canvas.addEventListener('mouseleave', () => { drawing = false; });
  canvas.addEventListener('touchstart', e => { e.preventDefault(); drawing = true; const p = getPos(e); ctx.beginPath(); ctx.moveTo(p.x, p.y); });
  canvas.addEventListener('touchmove', e => { e.preventDefault(); if (!drawing) return; const p = getPos(e); ctx.lineTo(p.x, p.y); ctx.stroke(); });
  canvas.addEventListener('touchend', () => { drawing = false; });
  document.getElementById('clearBtn').onclick = () => ctx.clearRect(0, 0, canvas.width, canvas.height);
  document.getElementById('confirmBtn').onclick = () => {
    signatureData = canvas.toDataURL();
    signatureDataUrl = signatureData;
    document.getElementById('signatureEditImg').src = signatureData;
    document.getElementById('signatureAutograph').style.display = '';
    var ph = document.getElementById('signaturePlaceholderDiv');
    if (ph) ph.style.display = 'none';
    saveFormCache();
    document.body.removeChild(popup);
  };
  popup.addEventListener('click', function(e) { if (e.target === popup) document.body.removeChild(popup); });
}
function removeSignature() {
  clearSignatureUi();
  saveFormCache();
}

// ===== 图片查看器 =====
function viewFacePhoto() {
  var src = facePhotoDataUrl || DEFAULT_FACE_PHOTO_URL;
  showImageViewer(src);
}
function viewSignature() {
  var src = signatureDataUrl || DEFAULT_SIGNATURE_URL;
  if (!src) return;
  showImageViewer(src);
}
function showImageViewer(src) {
  var overlay = document.createElement('div');
  overlay.style.cssText = 'position:fixed;top:0;left:0;right:0;bottom:0;background:rgba(0,0,0,.9);z-index:9999;display:flex;align-items:center;justify-content:center;';
  overlay.innerHTML = '<img src="'+src+'" style="max-width:95%;max-height:95%;object-fit:contain;border-radius:4px;">';
  overlay.addEventListener('click', function(){ document.body.removeChild(overlay); });
  document.body.appendChild(overlay);
}

// ===== 表单提交 =====
function handleSubmit() {
  const leaveType = document.getElementById('leaveTypeSelect').value;
  const startTime = document.getElementById('startTimeInput').value;
  const endTime = document.getElementById('endTimeInput').value;
  const applyDate = document.getElementById('applyDateInput').value;
  const dorm = document.getElementById('dormInput').value.trim();

  if (!facePhotoFile) return showToast('请上传面部照片');
  if (!leaveType) return showToast('请选择请假类型');
  if (!startTime) return showToast('请选择请假开始时间');
  if (!endTime) return showToast('请选择请假结束时间');
  if (new Date(endTime) <= new Date(startTime)) return showToast('结束时间必须晚于开始时间');
  if (!applyDate) return showToast('请选择请假申请时间');
  if (!signatureData) return showToast('请完成本人签名');

  const btn = document.getElementById('submitBtn');
  btn.disabled = true;
  btn.textContent = '提交中...';

  const leaveCampus = document.getElementById('leaveCampusSelect').value;
  const leaveCity = document.getElementById('leaveCitySelect').value;
  const leaveProvince = document.getElementById('leaveProvinceSelect').value;

  setTimeout(() => {
    switchToDetailMode({ leaveType, startTime, endTime, applyDate, dorm, leaveCampus, leaveCity, leaveProvince });
    showToast('请假申请提交成功！');
  }, 1200);
}

// ===== 切换到详情模式 =====
function switchToDetailMode(data) {
  var formDetail = document.getElementById('forms-detail');
  if (formDetail) formDetail.classList.remove('form-detail--footer-space');

  // 隐藏底部按钮
  document.getElementById('footerBar').style.display = 'none';

  // 更新顶部状态
  document.getElementById('detailStatus').textContent = '[已通过]';
  document.getElementById('detailStatus').style.cssText = '';
  document.getElementById('detailStatus').className = 'approve-header__status flow-status owt2 agreeColor';

  // 更新宿舍号
  document.getElementById('dormInput').style.display = 'none';
  document.getElementById('dormDisplay').style.display = '';
  if (data.dorm) document.getElementById('dormDisplayText').textContent = data.dorm;

  // 更新姓名
  document.getElementById('studentNameInput').style.display = 'none';
  document.getElementById('studentNameDisplay').style.display = '';
  document.getElementById('studentNameDisplay').textContent = document.getElementById('studentNameInput').value;

  // 更新学号
  document.getElementById('studentIdInput').style.display = 'none';
  document.getElementById('studentIdDisplay').style.display = '';
  document.getElementById('studentIdDisplay').textContent = document.getElementById('studentIdInput').value;

  // 更新年级
  document.getElementById('gradeInput').style.display = 'none';
  document.getElementById('gradeDisplay').style.display = '';
  document.getElementById('gradeDisplay').textContent = document.getElementById('gradeInput').value;

  // 更新院系
  document.getElementById('deptInput').style.display = 'none';
  document.getElementById('deptDisplay').style.display = '';
  document.getElementById('deptDisplay').textContent = document.getElementById('deptInput').value;

  // 更新专业
  document.getElementById('majorInput').style.display = 'none';
  document.getElementById('majorDisplay').style.display = '';
  document.getElementById('majorDisplay').textContent = document.getElementById('majorInput').value;

  // 更新班级
  document.getElementById('classNameInput').style.display = 'none';
  document.getElementById('classNameDisplay').style.display = '';
  document.getElementById('classNameDisplay').textContent = document.getElementById('classNameInput').value;

  // 更新辅导员姓名
  document.getElementById('counselorNameInput').style.display = 'none';
  document.getElementById('counselorNameDisplay').style.display = '';
  document.getElementById('counselorNameDisplay').textContent = document.getElementById('counselorNameInput').value;

  // 更新辅导员工号
  document.getElementById('counselorIdInput').style.display = 'none';
  document.getElementById('counselorIdDisplay').style.display = '';
  document.getElementById('counselorIdDisplay').textContent = document.getElementById('counselorIdInput').value;

  // 更新面部照片 -> 显示文件列表样式
  document.getElementById('facePhotoEdit').style.display = 'none';
  document.getElementById('facePhotoDetail').style.display = '';
  document.getElementById('faceFileNameDisp').textContent = facePhotoFile ? facePhotoFile.name : '';
  document.getElementById('faceFileSizeDisp').textContent = facePhotoFile && facePhotoFile.size ? (facePhotoFile.size/1024).toFixed(2)+'KB' : '--';

  // 更新请假类型
  document.getElementById('leaveTypeEdit').style.display = 'none';
  document.getElementById('leaveTypeDisplay').style.display = 'none';
  document.getElementById('leaveTypeDetailDisplay').style.display = '';
  document.getElementById('leaveTypeDispText2').textContent = data.leaveType;

  // 更新是否出校/市/省
  document.getElementById('leaveCampusEdit').style.display = 'none';
  document.getElementById('leaveCampusDisplay').style.display = '';
  document.getElementById('leaveCampusDispText').textContent = data.leaveCampus;
  document.getElementById('leaveCityEdit').style.display = 'none';
  document.getElementById('leaveCityDisplay').style.display = '';
  document.getElementById('leaveCityDispText').textContent = data.leaveCity;
  document.getElementById('leaveProvinceEdit').style.display = 'none';
  document.getElementById('leaveProvinceDisplay').style.display = '';
  document.getElementById('leaveProvinceDispText').textContent = data.leaveProvince;

  // 更新时间
  document.getElementById('startTimeInput').style.display = 'none';
  document.getElementById('startTimeDisplay').style.display = '';
  document.getElementById('startTimeDispText').textContent = data.startTime.replace('T',' ');
  document.getElementById('endTimeInput').style.display = 'none';
  document.getElementById('endTimeDisplay').style.display = '';
  document.getElementById('endTimeDispText').textContent = data.endTime.replace('T',' ');
  document.getElementById('applyDateInput').style.display = 'none';
  document.getElementById('applyDateDisplay').style.display = '';
  document.getElementById('applyDateDispText').textContent = data.applyDate;

  // 更新签名
  document.getElementById('signatureEdit').style.display = 'none';
  document.getElementById('signatureDetail').style.display = '';
  document.getElementById('signatureDetailImg').src = signatureDataUrl || DEFAULT_SIGNATURE_URL;

  // 模拟审批时间：提交时间为申请日10:18，审批同日晚20:58
  const submitTime = data.applyDate + ' 10:18:28';
  const approveTime = data.applyDate + ' 20:58:52';

  // 审批流程
  document.getElementById('approvalFlow').style.display = '';
  document.getElementById('approvalList').innerHTML =
    '<div data-v-b7090ed1="" data-v-6fee8692="" class="pass_per">'+
      '<img data-v-f9ab1735="" src="'+currentUser.avatar+'" class="pass_user_img">'+
      '<span data-v-f9ab1735="" class="pass_type_icon agree"></span>'+
      '<em data-v-f9ab1735="" class="pass_per_line"></em>'+
      '<div data-v-f9ab1735="" class="flow-user">'+
        '<div data-v-f9ab1735="" class="flow-user__head"></div>'+
        '<div data-v-f9ab1735="" class="flow-user__info">'+
          '<div data-v-f9ab1735="" class="flow-user__top"><div data-v-f9ab1735="" class="flow-user__name">发起申请</div><div data-v-f9ab1735="" class="flow-user__time">'+submitTime+'</div></div>'+
          '<div data-v-f9ab1735="" class="flow-user__desc"><p data-v-f9ab1735="" class="flow-user__desc-info">我</p></div>'+
          '<div data-v-b7090ed1="" class="aprv-flow-info"></div>'+
        '</div>'+
      '</div>'+
    '</div>'+
    '<div class="pass_per">'+
      '<img data-v-f9ab1735="" src="https://office-static.chaoxing.com/oa/static/style/apps/forms/web/new/images/pass_img_dr.png" class="pass_user_img">'+
      '<span data-v-f9ab1735="" class="pass_type_icon agree"></span>'+
      '<div data-v-f9ab1735="" class="flow-user">'+
        '<div data-v-f9ab1735="" class="flow-user__head"></div>'+
        '<div data-v-f9ab1735="" class="flow-user__info">'+
          '<div data-v-f9ab1735="" class="flow-user__top"><div data-v-f9ab1735="" class="flow-user__name">辅导员</div><div data-v-f9ab1735="" class="flow-user__time">'+approveTime+'</div></div>'+
          '<div data-v-f9ab1735="" class="flow-user__desc"><div class="flow-user__desc"><div class="flow-user__desc-info">辅导员角色或签</div><div class="flow-user__desc-line"></div><div class="flow-user__status pass_type_tip agreeColor">同意</div></div></div>'+
        '</div>'+
      '</div>'+
      '<div data-v-503b7a79="" class="pass_idea"><div data-v-503b7a79="" class="pass_idea_per">'+
        '<div data-v-f9ab1735="" class="flow-user">'+
          '<div data-v-f9ab1735="" class="flow-user__head"><img data-v-503b7a79="" src="'+currentUser.counselorAvatar+'" alt="" class="flow-user__head-img"></div>'+
          '<div data-v-f9ab1735="" class="flow-user__info">'+
            '<div data-v-f9ab1735="" class="flow-user__top"><div data-v-f9ab1735="" class="flow-user__name">'+currentUser.counselorName+'</div><div data-v-f9ab1735="" class="flow-user__time">'+approveTime+'</div></div>'+
            '<div data-v-f9ab1735="" class="flow-user__desc"><div data-v-503b7a79="" class="flow-user__status pass_type_tip agreeColor">同意</div><div data-v-503b7a79="" class="flow-user__desc-line"></div></div>'+
          '</div>'+
        '</div>'+
      '</div></div>'+
    '</div>';

  // 评论
  document.getElementById('commentSection').style.display = '';

  // 数据日志
  document.getElementById('dataLogSection').style.display = '';
  document.getElementById('dataLogList').innerHTML =
    '<div data-v-6545c99f="" data-v-cefb6c9b="" class="data-log-per">'+
      '<div data-v-fbbf6174="" data-v-6545c99f="" class="data-introduce">'+
        '<img data-v-fbbf6174="" src="'+currentUser.counselorAvatar+'" alt="" class="prev-user-img">'+
        '<span data-v-fbbf6174="" class="prev-user-name">'+currentUser.counselorName+'</span>'+
        '<span data-v-fbbf6174="" class="data-log-type aprv">处理</span>'+
        '<span data-v-fbbf6174="" class="data-log-word">了这条数据</span>'+
        '<span data-v-fbbf6174="" class="data-log-time">'+approveTime+'</span>'+
      '</div>'+
      '<ul data-v-6545c99f="" class="data-log-list"><div data-v-653e4663="" data-v-6545c99f=""><li data-v-653e4663="" class="data-field-info"><div data-v-653e4663="" class="data-introduce">进行了 同意 操作 <span data-v-653e4663="" class="data-log-word"></span></div></li></div></ul>'+
    '</div>'+
    '<div data-v-6545c99f="" data-v-cefb6c9b="" class="data-log-per">'+
      '<div data-v-fbbf6174="" data-v-6545c99f="" class="data-introduce">'+
        '<img data-v-fbbf6174="" src="'+currentUser.avatar+'" alt="" class="prev-user-img">'+
        '<span data-v-fbbf6174="" class="prev-user-name">'+currentUser.name+'</span>'+
        '<span data-v-fbbf6174="" class="data-log-type create">创建</span>'+
        '<span data-v-fbbf6174="" class="data-log-word">了这条数据</span>'+
        '<span data-v-fbbf6174="" class="data-log-time">'+submitTime+'</span>'+
      '</div>'+
    '</div>';

  window.scrollTo({ top: 0, behavior: 'smooth' });
}

function handleCancel() {
  if (confirm('确定要取消吗？已填写的信息将不会保存。')) {
    showToast('已取消');
  }
}

function syncName(val) {
  currentUser.name = val;
  document.getElementById('detailName').textContent = val;
  document.getElementById('detailTitle').textContent = val + '的请假';
  document.getElementById('avatarPreview').alt = val;
}

function syncHeaderInfo() {
  var sno = document.getElementById('studentIdInput').value;
  var dept = document.getElementById('deptInput').value;
  var major = document.getElementById('majorInput').value;
  var cls = document.getElementById('classNameInput').value;
  currentUser.sno = sno;
  currentUser.dept = dept;
  currentUser.major = major;
  currentUser.className = cls;
  document.getElementById('detailSno').textContent = sno;
  document.getElementById('detailDept').textContent = '学生\\' + dept + '\\' + major + '\\' + cls;
}

function syncCounselorName(val) {
  currentUser.counselorName = val;
}

function showToast(msg) {
  const existing = document.querySelector('.toast-real');
  if (existing) existing.remove();
  const toast = document.createElement('div');
  toast.className = 'toast-real';
  toast.textContent = msg;
  document.body.appendChild(toast);
  setTimeout(() => toast.remove(), 2000);
}
