if (typeof window === 'undefined') {
    self.addEventListener('install', function () {
        self.skipWaiting();
    });
    self.addEventListener('activate', function (event) {
        event.waitUntil(self.clients.claim());
    });
    self.addEventListener('fetch', function (event) {
        if (event.request.cache === 'only-if-cached' &&
            event.request.mode !== 'same-origin') {
            return;
        }
        event.respondWith(
            fetch(event.request)
                .then(function (response) {
                    const newHeaders = new Headers(response.headers);
                    newHeaders.set('Cross-Origin-Embedder-Policy',
                                   'require-corp');
                    newHeaders.set('Cross-Origin-Opener-Policy',
                                   'same-origin');
                    const moddedResponse = new Response(response.body, {
                        status: response.status,
                        statusText: response.statusText,
                        headers: newHeaders,
                    });
                    return moddedResponse;
                })
                .catch(function (e) {
                    console.error(e);
                }));
    });
} else {
    if ('serviceWorker' in navigator) {
        navigator.serviceWorker.register(
            window.document.currentScript.src).then(
                function (registration) {
                    console.log('Registered ServiceWorker');
                    registration.addEventListener('updatefound', function() {
                        console.log('Reloading to update');
                        window.location.reload();
                    });
                    if (registration.active &&
                        !navigator.serviceWorker.controller) {
                        console.log('Reloading to control the page');
                        window.location.reload();
                    }
                },
                function (err) {
                    console.log('Failed to register ServiceWorker', err);
                });
    } else {
        console.log('ServiceWorker is unavailable');
    }
}
