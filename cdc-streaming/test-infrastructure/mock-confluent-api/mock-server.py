#!/usr/bin/env python3
"""
Mock Confluent Flink API Server
Simulates Confluent Cloud Flink API for local testing
"""
from flask import Flask, jsonify, request
import uuid
import os

app = Flask(__name__)
statements = {}

@app.route('/v1/compute-pools/<pool_id>/statements', methods=['POST'])
def create_statement(pool_id):
    """Mock Flink statement deployment"""
    data = request.json
    stmt_id = f"stmt-{uuid.uuid4().hex[:8]}"
    statements[stmt_id] = {
        "id": stmt_id,
        "name": data.get("name"),
        "statement": data.get("statement"),
        "status": "RUNNING"
    }
    return jsonify(statements[stmt_id]), 201

@app.route('/v1/compute-pools/<pool_id>/statements/<stmt_id>', methods=['GET'])
def get_statement(pool_id, stmt_id):
    """Get statement status"""
    if stmt_id in statements:
        return jsonify(statements[stmt_id])
    return jsonify({"error": "Not found"}), 404

@app.route('/v1/compute-pools/<pool_id>/statements/<stmt_id>', methods=['DELETE'])
def delete_statement(pool_id, stmt_id):
    """Delete statement"""
    if stmt_id in statements:
        del statements[stmt_id]
        return '', 204
    return jsonify({"error": "Not found"}), 404

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({"status": "healthy"}), 200

if __name__ == '__main__':
    port = int(os.environ.get('MOCK_API_PORT', 8082))
    app.run(host='0.0.0.0', port=port, debug=False)

