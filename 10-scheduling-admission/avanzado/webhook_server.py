import http.server, ssl, json

class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers['Content-Length'])
        body = json.loads(self.rfile.read(length))
        req = body["request"]
        uid = req["uid"]
        pod = req["object"]
        allowed = True
        message = ""
        for c in pod.get("spec", {}).get("containers", []):
            image = c.get("image", "")
            if image.endswith(":latest") or ":" not in image:
                allowed = False
                message = f"Imagen '{image}' usa tag ':latest' (o ninguno) — prohibido por politica de admision"
                break
        response = {
            "apiVersion": "admission.k8s.io/v1",
            "kind": "AdmissionReview",
            "response": {
                "uid": uid,
                "allowed": allowed,
                "status": {"message": message} if not allowed else {"message": "ok"}
            }
        }
        data = json.dumps(response).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):
        print("LOG:", fmt % args)

httpd = http.server.HTTPServer(("0.0.0.0", 8443), Handler)
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(certfile="/certs/tls.crt", keyfile="/certs/tls.key")
httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)
httpd.serve_forever()
