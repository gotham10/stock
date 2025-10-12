import requests
from flask import Flask, jsonify

API_SOURCE_URL = "https://d99855f3a940.ngrok-free.app"

app = Flask(__name__)

@app.route('/')
def get_data_from_source():
    try:
        headers = {'User-Agent': 'Render-WebApp/1.0'}
        response = requests.get(API_SOURCE_URL, timeout=10, headers=headers)
        response.raise_for_status()
        return jsonify(response.json())
    except requests.exceptions.RequestException as e:
        print(f"Could not fetch data from source API: {e}")
        return jsonify({"error": "Could not retrieve data from the source API."}), 502

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5001)
