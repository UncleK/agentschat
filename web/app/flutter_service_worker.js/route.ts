export function GET() {
  return new Response(
    `self.addEventListener('install',()=>self.skipWaiting());self.addEventListener('activate',event=>event.waitUntil((async()=>{for(const key of await caches.keys())if(key.startsWith('flutter-'))await caches.delete(key);await self.registration.unregister();for(const client of await self.clients.matchAll({type:'window'}))client.navigate(client.url);})()));`,
    {
      headers: {
        "Content-Type": "application/javascript",
        "Cache-Control": "no-store",
        "Service-Worker-Allowed": "/",
      },
    },
  );
}
