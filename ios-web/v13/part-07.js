  if(remote) countSyncTimer=setTimeout(async()=>{
    try{
      await api('draft_sync',{
        employee:count.employee,
        status:'in_progress',
        started_at:count.started_at,
        active_seconds:count.active_seconds,
        filled_count:count.lines.filter(filledCountLine).length,
        total_count:count.lines.length,
        payload:{
          last_product_key:count.lastProductKey||null,
          lines:count.lines.map(l=>({...l,whole_packages:l.whole,extra_amount:l.extra}))
        }
      },true);
    }catch(_){}
  },500);
};

// Persist UI filter state locally.
try{const saved=JSON.parse(localStorage.getItem('bali_v13_filters')||'null');if(saved?.stock)Object.assign(__v13StockFilter,saved.stock);if(saved?.history)Object.assign(__v13HistoryFilter,saved.history)}catch(_){}
setInterval(()=>{try{localStorage.setItem('bali_v13_filters',JSON.stringify({stock:__v13StockFilter,history:__v13HistoryFilter}))}catch(_){}},3000);

// Expose version for diagnostics.
window.BALI_STOCK_MOBILE_VERSION=V13_VERSION;
