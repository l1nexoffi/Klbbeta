/* KLB STORE Supabase integration starter. Load Supabase v2 CDN before this file. */
(() => {
  const cfg = window.KLB_SUPABASE_CONFIG;
  if (!cfg || !cfg.url || !cfg.anonKey || cfg.url.includes('YOUR_PROJECT')) {
    window.KLBBackend = { configured: false, message: 'Supabase configuration is missing.' };
    return;
  }
  const sb = window.supabase.createClient(cfg.url, cfg.anonKey);
  const usernameEmail = username => `${String(username).trim().toLowerCase().replace(/[^a-z0-9_]/g, '')}@login.klbstore.invalid`;
  const api = {
    configured: true,
    client: sb,
    async register(username, password) {
      const clean = String(username).trim();
      if (!/^[a-zA-Z0-9_]{3,24}$/.test(clean)) throw new Error('Логин: 3–24 символа, латиница, цифры и _');
      const { data, error } = await sb.auth.signUp({ email: usernameEmail(clean), password, options: { data: { username: clean } } });
      if (error) throw error;
      if (!data.user) throw new Error('Не удалось создать пользователя.');
      return data.user;
    },
    async login(username, password) {
      const { data, error } = await sb.auth.signInWithPassword({ email: usernameEmail(username), password });
      if (error) throw error;
      const profile = await api.profile();
      if (profile?.status === 'blocked') { await sb.auth.signOut(); throw new Error('Аккаунт заблокирован.'); }
      return profile;
    },
    async logout() { const { error } = await sb.auth.signOut(); if (error) throw error; },
    async session() { const { data, error } = await sb.auth.getSession(); if (error) throw error; return data.session; },
    async profile() {
      const session = await api.session(); if (!session) return null;
      const { data, error } = await sb.from('profiles').select('*').eq('id', session.user.id).single();
      if (error) throw error; return data;
    },
    async products() { const { data, error } = await sb.from('products').select('*').eq('status','active').order('created_at',{ascending:false}); if(error) throw error; return data; },
    async submitSellerApplication(payload) { const { data, error } = await sb.from('seller_applications').insert(payload).select().single(); if(error) throw error; return data; },
    async sellerApplications() { const { data, error } = await sb.from('seller_applications').select('*').order('created_at',{ascending:false}); if(error) throw error; return data; },
    async reviewSellerApplication(id, approved) {
      const { data, error } = await sb.from('seller_applications').update({status: approved ? 'approved' : 'rejected', reviewed_at: new Date().toISOString()}).eq('id',id).select().single();
      if(error) throw error;
      if(approved) { const { error: roleError } = await sb.from('profiles').update({role:'seller'}).eq('id',data.user_id); if(roleError) throw roleError; }
      return data;
    },
    async createOrder(product) { const session=await api.session(); if(!session) throw new Error('Войдите, чтобы оформить заказ.'); const { data,error }=await sb.from('orders').insert({buyer_id:session.user.id,seller_id:product.seller_id,product_id:product.id,product_title:product.title,amount:product.price}).select().single(); if(error) throw error; return data; },
    async myOrders() { const { data,error }=await sb.from('orders').select('*').order('created_at',{ascending:false}); if(error) throw error; return data; },
    async favorites() { const { data,error }=await sb.from('favorites').select('product_id'); if(error) throw error; return data.map(x=>x.product_id); },
    async toggleFavorite(productId) { const ids=await api.favorites(); if(ids.includes(productId)){const {error}=await sb.from('favorites').delete().eq('product_id',productId);if(error)throw error;return false;}const {error}=await sb.from('favorites').insert({product_id:productId});if(error)throw error;return true; },
    async isAdmin() { const p=await api.profile(); return p?.role==='admin'&&p.status==='active'; }
  };
  window.KLBBackend = api;
})();
