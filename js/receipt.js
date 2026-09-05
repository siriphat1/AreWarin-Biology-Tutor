(() => {
  'use strict';
  const esc = v => String(v ?? '').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
  const money = v => Number(v || 0).toLocaleString('th-TH',{minimumFractionDigits:2,maximumFractionDigits:2});
  const dateTH = v => v ? new Date(v).toLocaleString('th-TH',{dateStyle:'medium',timeStyle:'short'}) : '-';

  async function fetchReceipt(token){
    const sb = window.AreWarinAPI?.sb;
    if(!sb) throw new Error('ยังไม่ได้เชื่อม Supabase');
    const {data,error}=await sb.functions.invoke('get-receipt',{body:{receiptToken:token}});
    if(error) throw new Error(error.message || 'โหลดใบเสร็จไม่สำเร็จ');
    if(!data?.success) throw new Error(data?.message || 'ไม่พบใบเสร็จ');
    return data;
  }

  function receiptHTML(data){
    const e=data.enrollment||{}, p=data.payment||{}, r=data.settings||{};
    const paid=p.status==='paid';
    const amount=paid ? (p.verified_amount ?? e.amount_quoted) : e.amount_quoted;
    const promo=e.promotion_code ? `<tr><td style="padding:5px 0;color:#64748b">โปรโมชั่น</td><td style="padding:5px 0;text-align:right">${esc(e.promotion_code)}</td></tr>` : '';
    const logo=r.show_logo && data.logoUrl ? `<img src="${esc(data.logoUrl)}" crossorigin="anonymous" style="max-width:78px;max-height:78px;object-fit:contain;margin-bottom:10px">` : '';
    const sig=r.show_signature && data.signatureUrl ? `<img src="${esc(data.signatureUrl)}" crossorigin="anonymous" style="max-width:150px;max-height:58px;object-fit:contain;margin:0 auto 4px">` : '';
    return `
    <div style="font-family:'Prompt','Noto Sans Thai',sans-serif;background:#fff;color:#172033;width:794px;min-height:1123px;padding:54px 58px;box-sizing:border-box">
      <div style="display:flex;justify-content:space-between;gap:30px;border-bottom:2px solid #0f172a;padding-bottom:24px">
        <div style="display:flex;gap:16px;align-items:flex-start">${logo}<div><div style="font-size:20px;font-weight:700">${esc(r.business_name||'กวดวิชาชีววิทยา อาวริน')}</div><div style="font-size:11px;color:#64748b;margin-top:3px">${esc(r.business_name_en||'AreWarin Biology')}</div><div style="font-size:10px;color:#64748b;line-height:1.7;margin-top:9px;max-width:390px">${esc(r.address||'')}</div><div style="font-size:10px;color:#64748b;margin-top:3px">โทร ${esc(r.phone||'-')} ${r.tax_id?`• เลขประจำตัวผู้เสียภาษี ${esc(r.tax_id)}`:''}</div></div></div>
        <div style="text-align:right;min-width:220px"><div style="font-size:23px;font-weight:700">ใบเสร็จรับเงิน</div><div style="font-size:11px;color:#64748b">RECEIPT</div><div style="font-size:11px;margin-top:14px"><b>เลขที่:</b> ${esc(e.receipt_no||'-')}</div><div style="font-size:10px;color:#64748b;margin-top:4px">วันที่ออก: ${esc(dateTH(e.created_at))}</div></div>
      </div>
      <div style="margin-top:28px;border:1px solid #e2e8f0;border-radius:14px;padding:18px 20px">
        <div style="font-size:10px;color:#94a3b8;text-transform:uppercase;letter-spacing:.08em">ผู้ชำระเงิน / Student</div>
        <div style="font-size:14px;font-weight:650;margin-top:5px">${esc(e.fullname||'-')}</div>
        <div style="font-size:10px;color:#64748b;margin-top:4px">${esc(e.phone||'')} ${e.school?`• ${esc(e.school)}`:''}</div>
      </div>
      <table style="width:100%;border-collapse:collapse;margin-top:24px;font-size:11px">
        <thead><tr style="background:#f8fafc;border-top:1px solid #e2e8f0;border-bottom:1px solid #e2e8f0"><th style="padding:12px;text-align:left">รายการ</th><th style="padding:12px;text-align:right;width:150px">จำนวนเงิน</th></tr></thead>
        <tbody><tr style="border-bottom:1px solid #eef2f7"><td style="padding:16px 12px"><div style="font-weight:650;font-size:12px">${esc(e.course_text||'-')}</div><div style="font-size:10px;color:#64748b;margin-top:5px">ติวเตอร์: ${esc(e.tutor_text||'-')}</div><div style="font-size:10px;color:#64748b;margin-top:3px">แพ็กเกจ: ${esc(e.mode_text||'-')} ${e.hours_text?`• ${esc(e.hours_text)}`:''}</div><div style="font-size:10px;color:#64748b;margin-top:3px">เวลา: ${esc(e.time_text||'-')}</div></td><td style="padding:16px 12px;text-align:right;font-weight:650">${money(e.amount_quoted)} บาท</td></tr></tbody>
      </table>
      <div style="display:flex;justify-content:flex-end;margin-top:18px"><table style="width:330px;font-size:11px;border-collapse:collapse"><tbody>${promo}<tr style="border-top:1px solid #cbd5e1"><td style="padding:10px 0;font-weight:650">ยอดสุทธิ</td><td style="padding:10px 0;text-align:right;font-size:16px;font-weight:700">${money(amount)} บาท</td></tr><tr><td style="padding:4px 0;color:#64748b">วิธีชำระเงิน</td><td style="padding:4px 0;text-align:right">${p.payment_method==='cash'?'เงินสด':'โอนเงิน'}</td></tr><tr><td style="padding:4px 0;color:#64748b">สถานะ</td><td style="padding:4px 0;text-align:right;font-weight:650;color:${paid?'#059669':'#d97706'}">${paid?'ชำระเงินแล้ว':'รอตรวจสอบการชำระเงิน'}</td></tr>${paid&&p.verified_at?`<tr><td style="padding:4px 0;color:#64748b">ยืนยันเมื่อ</td><td style="padding:4px 0;text-align:right">${esc(dateTH(p.verified_at))}</td></tr>`:''}</tbody></table></div>
      <div style="margin-top:68px;display:flex;justify-content:flex-end"><div style="width:240px;text-align:center">${sig}<div style="border-top:1px solid #94a3b8;padding-top:7px;font-size:10px;font-weight:600">${esc(r.signer_name||'')}</div><div style="font-size:9px;color:#64748b;margin-top:2px">${esc(r.signer_position||'ผู้รับเงิน')}</div></div></div>
      <div style="position:relative;margin-top:70px;border-top:1px dashed #cbd5e1;padding-top:15px;text-align:center;font-size:9px;color:#94a3b8;line-height:1.7">${esc(r.footer_text||'ขอบคุณที่ไว้วางใจ AreWarin Biology')}<br>เอกสารนี้ออกจากระบบ AreWarin Manager</div>
    </div>`;
  }

  async function download(token){
    if(!token) throw new Error('ไม่พบรหัสใบเสร็จ');
    const data=await fetchReceipt(token);
    const wrap=document.createElement('div');
    wrap.style.position='fixed';wrap.style.left='-10000px';wrap.style.top='0';wrap.innerHTML=receiptHTML(data);document.body.appendChild(wrap);
    try{
      const no=data.enrollment?.receipt_no || 'receipt';
      await window.html2pdf().set({margin:0,filename:`${no}.pdf`,image:{type:'jpeg',quality:.98},html2canvas:{scale:2,useCORS:true,backgroundColor:'#ffffff'},jsPDF:{unit:'px',format:[794,1123],orientation:'portrait'}}).from(wrap.firstElementChild).save();
    } finally { wrap.remove(); }
  }

  window.AreWarinReceipt={fetch:fetchReceipt,download};
})();
