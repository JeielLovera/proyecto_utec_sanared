#!/usr/bin/env python3
"""Probe mTLS del ALB privado (perimetro de admision) usado por test_admision_mtls.sh.

Se ejecuta DENTRO del contenedor 'empi' via ECS Exec (misma VPC que el ALB
interno). Usa solo la stdlib para no depender de paquetes extra en la imagen.
"""
import sys
import ssl
import http.client

def main() -> int:
    if len(sys.argv) < 6:
        print("uso: mtls_admision_probe.py <cert> <key> <ca> <host> <path> [method] [body]", file=sys.stderr)
        return 2

    cert_path, key_path, ca_path, host, path = sys.argv[1:6]
    method = sys.argv[6] if len(sys.argv) > 6 else "GET"
    body = sys.argv[7] if len(sys.argv) > 7 else None

    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.load_verify_locations(cafile=ca_path)
    ctx.load_cert_chain(certfile=cert_path, keyfile=key_path)
    # El cert de servidor del ALB usa CN=empi.internal.sanared (nombre logico de
    # demo, no coincide con el DNS real del ALB) -> se valida la cadena contra
    # la CA pero no el hostname, igual que haria el cliente real de Admision
    # apuntando a un nombre interno propio via /etc/hosts o DNS privado.
    ctx.check_hostname = False

    body_bytes = body.encode("utf-8") if body else None
    headers = {"content-type": "application/json", "content-length": str(len(body_bytes))} if body_bytes else {}
    conn = http.client.HTTPSConnection(host, 443, context=ctx, timeout=15)
    try:
        conn.request(method, path, body=body_bytes, headers=headers)
        resp = conn.getresponse()
        data = resp.read().decode(errors="replace")
        peer_cert = conn.sock.getpeercert()
        print("mTLS OK - conexion establecida y cert de servidor validado contra la CA")
        print(f"server cert subject: {peer_cert.get('subject')}")
        print(f"HTTP {resp.status} {resp.reason}")
        print(data)
        return 0 if 200 <= resp.status < 500 else 1
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
