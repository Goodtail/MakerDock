# Local test fixture. Never connects to a real printer or Bambu service.
import json, socket, ssl, sys
from pathlib import Path
root = Path(sys.argv[1])
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(str(root/'server.pem'), str(root/'server.key'))
listener = socket.socket()
listener.bind(('127.0.0.1', 0)); listener.listen(1); listener.settimeout(8)
(root/'port').write_text(str(listener.getsockname()[1]))
def read_packet(sock):
    def read(n):
        result = b''
        while len(result) < n:
            more = sock.recv(n-len(result))
            if not more: raise EOFError()
            result += more
        return result
    header = read(1)[0]; length = 0; multiplier = 1
    for _ in range(4):
        digit = read(1)[0]; length += (digit & 127) * multiplier
        if digit < 128: break
        multiplier *= 128
    assert length < 65536
    return header, read(length)
def publish(fields):
    topic = b'device/TEST123/report'
    body = len(topic).to_bytes(2,'big') + topic + b'\x00\x07' + json.dumps({'print':fields}).encode()
    length=len(body); encoded=b''
    while True:
        digit=length % 128; length //= 128
        encoded += bytes([digit | (128 if length else 0)])
        if not length: break
    return b'\x32'+encoded+body
try:
    raw, _ = listener.accept()
    with context.wrap_socket(raw, server_side=True) as sock:
        sock.settimeout(8)
        header, body = read_packet(sock)
        assert header == 0x10 and b'bblp' in body and b'DUMMY123' in body
        sock.sendall(b'\x20\x02\x00\x00')
        header, body = read_packet(sock)
        assert header == 0x82 and body == b'\x00\x01\x00\x15device/TEST123/report\x00'
        sock.sendall(b'\x90\x03\x00\x01\x00')
        packet = publish({'gcode_state':'RUNNING','subtask_id':'42','mc_remaining_time':30})
        sock.sendall(packet[:3]); sock.sendall(packet[3:])
        header, body = read_packet(sock)
        assert header == 0x40 and body == b'\x00\x07'
        (root/'result').write_text('subscribed-and-acknowledged-without-commands')
except ssl.SSLError:
    (root/'result').write_text('tls-rejected-before-credentials')
except Exception as exc:
    (root/'result').write_text(type(exc).__name__)
finally:
    listener.close()
