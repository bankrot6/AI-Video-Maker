#!/bin/bash

API_KEY="AIzaSyCu7JJcOjXKPjCaopr4wyxXp7WkWAAKcZs"
PROJECT_ID="photosession-ai-cbfc3"
DOC_ID="test_preset_$(date +%s)"

curl -X POST \
  "https://firestore.googleapis.com/v1/projects/$PROJECT_ID/databases/(default)/documents/presets?documentId=$DOC_ID&key=$API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "fields": {
      "title": {"stringValue": "Test Preset"},
      "prompt": {"stringValue": "Test prompt for verification"},
      "previewImageUrl": {"stringValue": "https://example.com/test.jpg"},
      "tags": {
        "arrayValue": {
          "values": [
            {"stringValue": "test"}
          ]
        }
      },
      "createdAt": {"stringValue": "2026-03-17T13:00:00.000000"}
    }
  }'
