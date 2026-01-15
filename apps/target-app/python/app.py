from flask import Flask, request, jsonify
import time

app = Flask(__name__)

@app.get('/healthz')
def healthz():
    return jsonify(status='ok'), 200

@app.get('/cpu')
def cpu():
    ms = int(request.args.get('ms', '100'))
    end = time.time() + (ms / 1000.0)
    x = 0
    while time.time() < end:
        x += 1
    return jsonify(result=x, ms=ms), 200

@app.get('/mem')
def mem():
    mb = int(request.args.get('mb', '100'))
    block = bytearray(mb * 1024 * 1024)
    for i in range(0, len(block), 4096):
        block[i] = 1
    return jsonify(allocated_mb=mb), 200

@app.get('/work')
def work():
    ms = int(request.args.get('ms', '100'))
    mb = int(request.args.get('mb', '100'))
    # CPU
    end = time.time() + (ms / 1000.0)
    x = 0
    while time.time() < end:
        x += 1
    # Memory
    block = bytearray(mb * 1024 * 1024)
    for i in range(0, len(block), 4096):
        block[i] = 1
    return jsonify(cpu_ms=ms, mem_mb=mb, result=x), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
