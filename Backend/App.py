# backend python:
# app.py

import os

#Setting this environment variable can help avoid crashes on some systems, especially macOS
os.environ["KMP_DUPLICATE_LIB_OK"] = "TRUE"

from flask import Flask, request, jsonify, render_template
from flask_cors import CORS
from flask_socketio import SocketIO, emit
from flask_sqlalchemy import SQLAlchemy
import cv2
import numpy as np
import torch
# import os # Already imported
import io
import base64
import logging
from PIL import Image
import easyocr
import torchvision.models as models
import torchvision.transforms as transforms
import requests
import time # For basic timing/logging if needed

# --- Logging Setup ---
logging.basicConfig(level=logging.DEBUG, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)
# logger.setLevel(logging.DEBUG) # Already set by basicConfig

template_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'templates'))
app = Flask(__name__, template_folder=template_dir)
CORS(app)
# Increase buffer size if needed for larger images, async_mode helps performance
socketio = SocketIO(app, cors_allowed_origins="*", max_http_buffer_size=10 * 1024 * 1024, async_mode='threading')

# --- Database Setup (Keep as is, ensure connection works independently) ---
# ... (DB setup remains the same) ...
app.config['SQLALCHEMY_DATABASE_URI'] = 'mysql+pymysql://root:@127.0.0.1:3306/visualaiddb'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
app.config['SQLALCHEMY_ECHO'] = True # Log SQL statements (can be verbose)
db = SQLAlchemy(app)

def test_db_connection():
    try:
        with app.app_context(): # Ensure we are in app context
            with db.engine.connect() as connection:
                result = connection.execute(db.text("SELECT 1"))
                logger.info("Database connection successful!")
                return True
    except Exception as e:
        logger.error(f"Database connection failed: {e}", exc_info=True)
        return False

class User(db.Model):
    __tablename__ = 'users'
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(255), nullable=False)
    email = db.Column(db.String(255), nullable=False, unique=True)
    password = db.Column(db.String(255), nullable=False)
    customization = db.Column(db.String(255), default='0' * 255)

with app.app_context():
    try:
        db.create_all()
        test_db_connection()
    except Exception as e:
        logger.error(f"Error during initial DB setup: {e}", exc_info=True)

# --- Model Loading ---
logger.info("Loading ML models...")
try:
    # YOLOv5 model for object detection (ensure internet connection on first run)
    # Consider downloading weights manually if offline use is needed
    logger.debug("Loading YOLOv5 model...")
    yolo_model = torch.hub.load('ultralytics/yolov5', 'yolov5n', device='cpu')
    logger.debug("YOLOv5 model loaded.")

    # Places365 model for scene detection
    def load_places365_model():
        logger.debug("Loading Places365 model...")
        model = models.resnet50(weights=None)
        model.fc = torch.nn.Linear(model.fc.in_features, 365)
        weights_path = 'resnet50_places365.pth.tar'
        if not os.path.exists(weights_path):
            logger.info(f"Downloading Places365 weights to {weights_path}...")
            try:
                response = requests.get('http://places2.csail.mit.edu/models_places365/resnet50_places365.pth.tar', timeout=30)
                response.raise_for_status() # Raise error for bad status codes
                with open(weights_path, 'wb') as f:
                    f.write(response.content)
                logger.info("Places365 weights downloaded.")
            except requests.exceptions.RequestException as req_e:
                logger.error(f"Failed to download Places365 weights: {req_e}")
                raise  # Re-raise to prevent server start if model is crucial
        else:
             logger.debug(f"Found existing Places365 weights at {weights_path}.")

        # Load checkpoint carefully
        try:
            checkpoint = torch.load(weights_path, map_location='cpu')
            # Handle potential inconsistencies in state_dict keys
            state_dict = checkpoint.get('state_dict', checkpoint) # Check if 'state_dict' key exists
            state_dict = {k.replace('module.', ''): v for k, v in state_dict.items()}
            model.load_state_dict(state_dict)
            logger.debug("Places365 model weights loaded successfully.")
            return model.eval()
        except Exception as load_e:
            logger.error(f"Error loading Places365 weights from file: {load_e}", exc_info=True)
            raise

    places_model = load_places365_model()

    # Places365 labels
    logger.debug("Loading Places365 labels...")
    places_labels = []
    try:
        response = requests.get('https://raw.githubusercontent.com/csailvision/places365/master/categories_places365.txt', timeout=10)
        response.raise_for_status()
        for line in response.text.split('\n'):
            if line:
                parts = line.split(' ')
                # Format label: /c/classroom -> classroom
                label = parts[0].split('/')[-1]
                places_labels.append(label)
        logger.debug(f"Loaded {len(places_labels)} Places365 labels.")
    except requests.exceptions.RequestException as req_e:
        logger.error(f"Failed to download Places365 labels: {req_e}")
        # Consider adding fallback or raising an error if labels are essential
        places_labels = [f"Label {i}" for i in range(365)] # Fallback

    # EasyOCR reader for text detection
    logger.debug("Loading EasyOCR reader...")
    # Specify GPU=False explicitly if you don't want GPU usage or don't have CUDA setup
    ocr_reader = easyocr.Reader(['en'], gpu=False)
    logger.debug("EasyOCR reader loaded.")

    # Image transforms for scene detection
    scene_transform = transforms.Compose([
        transforms.Resize((256, 256)),
        transforms.CenterCrop(224),
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
    ])
    logger.info("ML models loaded successfully.")

except Exception as e:
    logger.error(f"FATAL ERROR DURING MODEL LOADING: {e}", exc_info=True)
    # Depending on the app, you might want to exit here if models are essential
    # raise SystemExit("Failed to load critical ML models.")


# --- Detection Functions ---

def detect_objects(image_np):
    """Perform object detection using YOLOv5"""
    logger.debug("Starting object detection...")
    try:
        # Convert BGR (cv2 default) to RGB (PIL/YOLO default)
        img_rgb = cv2.cvtColor(image_np, cv2.COLOR_BGR2RGB)
        img_pil = Image.fromarray(img_rgb)

        results = yolo_model(img_pil)
        # Extract relevant info: name and confidence, filter by confidence
        detections = results.pandas().xyxy[0]
        filtered_detections = detections[detections['confidence'] > 0.4] # Adjust confidence threshold if needed

        # *** MODIFIED: Format output string WITHOUT confidence ***
        object_list = [row['name'] for index, row in filtered_detections.iterrows()]

        if not object_list:
            logger.debug("Object detection complete: No objects detected above threshold.")
            return "No objects detected"
        else:
            result_str = ", ".join(object_list) # Join names with comma and space
            logger.debug(f"Object detection complete: {result_str}")
            return result_str
    except Exception as e:
        logger.error(f"Error during object detection: {e}", exc_info=True)
        return "Error during object detection"

def detect_scene(image_np):
    """Perform scene classification using Places365"""
    logger.debug("Starting scene detection...")
    try:
        # Convert BGR (cv2 default) to RGB (PIL default)
        img_rgb = cv2.cvtColor(image_np, cv2.COLOR_BGR2RGB)
        img_pil = Image.fromarray(img_rgb)

        # Apply transforms
        img_tensor = scene_transform(img_pil).unsqueeze(0)

        with torch.no_grad():
            outputs = places_model(img_tensor)
            probabilities = torch.softmax(outputs, dim=1)[0] # Get probabilities
            # Get top prediction
            top_prob, top_catid = torch.max(probabilities, 0)
            predicted_label = places_labels[top_catid.item()]
            # confidence = top_prob.item() # We don't need confidence anymore

        # *** MODIFIED: Return only the label ***
        result_str = f"{predicted_label}"
        logger.debug(f"Scene detection complete: {result_str}")
        return result_str
    except Exception as e:
        logger.error(f"Error during scene detection: {e}", exc_info=True)
        return "Error during scene detection"

def detect_text(image_np):
    """Perform text detection using EasyOCR"""
    logger.debug("Starting text detection...")
    try:
        # EasyOCR generally works well with BGR
        results = ocr_reader.readtext(image_np)

        # Extract and join detected text
        detected_text_list = [result[1] for result in results]
        if not detected_text_list:
            logger.debug("Text detection complete: No text detected.")
            return "No text detected"
        else:
            result_str = " ".join(detected_text_list) # Join with spaces
            logger.debug(f"Text detection complete: Found text '{result_str[:100]}...'")
            return result_str # No confidence score here anyway
    except Exception as e:
        logger.error(f"Error during text detection: {e}", exc_info=True)
        return "Error during text detection"

# --- WebSocket Handlers ---
# ... (WebSocket handlers handle_connect, handle_disconnect, handle_message remain the same) ...
@socketio.on('connect')
def handle_connect():
    logger.info(f'Client connected: {request.sid}')
    # Send confirmation back to the specific client
    emit('response', {'result': 'Connected to VisionAid backend'})

@socketio.on('disconnect')
def handle_disconnect():
     logger.info(f'Client disconnected: {request.sid}')

@socketio.on('message') # Generic message handler used by Flutter app
def handle_message(data):
    client_sid = request.sid
    logger.debug(f"Received 'message' event from {client_sid}. Data keys: {list(data.keys()) if isinstance(data, dict) else type(data)}")

    start_time = time.time()
    try:
        # 1. Validate input data structure
        if not isinstance(data, dict):
            logger.warning(f"Invalid data format from {client_sid}. Expected dict, got {type(data)}.")
            emit('response', {'result': 'Error: Invalid data format (expected JSON object)'})
            return

        image_data = data.get('image')
        detection_type = data.get('type')

        if not image_data or not detection_type:
            logger.warning(f"Missing 'image' or 'type' field from {client_sid}.")
            emit('response', {'result': "Error: Missing 'image' or 'type' field in request"})
            return

        logger.info(f"Processing request from {client_sid}. Type: '{detection_type}'")

        # 2. Decode Base64 Image
        try:
            # Remove data URL prefix if present (e.g., "data:image/jpeg;base64,")
            if ',' in image_data:
                header, encoded = image_data.split(',', 1)
                # logger.debug(f"Removed data URL header: {header}") # Can be verbose
            else:
                encoded = image_data

            image_bytes = base64.b64decode(encoded)
            image_np = cv2.imdecode(np.frombuffer(image_bytes, np.uint8), cv2.IMREAD_COLOR)

            if image_np is None:
                logger.error(f"Failed to decode image from {client_sid}. Image data length (approx): {len(encoded)}")
                emit('response', {'result': 'Error: Failed to decode image data'})
                return
            logger.debug(f"Image decoded successfully from {client_sid}. Shape: {image_np.shape}")

        except base64.binascii.Error as b64e:
            logger.error(f"Base64 decoding error for {client_sid}: {b64e}", exc_info=True)
            emit('response', {'result': 'Error: Invalid Base64 image data'})
            return
        except Exception as decode_e:
             logger.error(f"Unexpected error decoding image for {client_sid}: {decode_e}", exc_info=True)
             emit('response', {'result': 'Error: Could not process image data'})
             return

        # 3. Process Image based on detection type
        result = "Error: Unsupported detection type specified" # Default error
        if detection_type == 'object_detection':
            result = detect_objects(image_np)
        elif detection_type == 'scene_detection':
            result = detect_scene(image_np)
        elif detection_type == 'text_detection':
            result = detect_text(image_np)
        else:
            logger.warning(f"Received unsupported detection type '{detection_type}' from {client_sid}")
            # Keep the default error message 'Unsupported detection type'

        processing_time = time.time() - start_time
        logger.info(f"Completed processing for {client_sid} (Type: {detection_type}). Time: {processing_time:.3f}s. Result: '{result[:100]}...'")

        # 4. Emit result back to the specific client
        emit('response', {'result': result})

    except Exception as e:
        processing_time = time.time() - start_time
        logger.error(f"Unhandled error processing message for {client_sid} after {processing_time:.3f}s: {e}", exc_info=True)
        # Send a generic error back to the client
        try:
            emit('response', {'result': f'Server Error: An unexpected error occurred.'})
        except Exception as emit_e:
            logger.error(f"Failed to emit error response to {client_sid}: {emit_e}")


# --- Test page handlers (modified to match new output format) ---
@socketio.on('detect-objects') # Used by test.html
def handle_object_detection_test(data):
    logger.debug("Received 'detect-objects' (for test page)")
    try:
        img_data = data.get('image')
        if not img_data:
            emit('object-detection-result', {'success': False, 'error': 'No image data provided'})
            return
        if ',' in img_data: header, encoded = img_data.split(',', 1)
        else: encoded = img_data
        img_bytes = base64.b64decode(encoded)
        image_np = cv2.imdecode(np.frombuffer(img_bytes, np.uint8), cv2.IMREAD_COLOR) # Decode to CV2 format
        if image_np is None: raise ValueError("Failed to decode image")
        # Call the updated function
        result_str = detect_objects(image_np)
        # Send back the string result, mimicking the main 'response' event
        emit('object-detection-result', {'success': True, 'detections': result_str})
    except Exception as e:
        logger.error(f"Error in 'detect-objects' handler: {e}", exc_info=True)
        emit('object-detection-result', {'success': False, 'error': str(e)})

@socketio.on('detect-scene') # Used by test.html
def handle_scene_detection_test(data):
    logger.debug("Received 'detect-scene' (for test page)")
    try:
        img_data = data.get('image')
        if not img_data:
            emit('scene-detection-result', {'success': False, 'error': 'No image data provided'})
            return
        if ',' in img_data: header, encoded = img_data.split(',', 1)
        else: encoded = img_data
        img_bytes = base64.b64decode(encoded)
        image_np = cv2.imdecode(np.frombuffer(img_bytes, np.uint8), cv2.IMREAD_COLOR) # Decode to CV2 format
        if image_np is None: raise ValueError("Failed to decode image")
        # Call the updated function
        result_str = detect_scene(image_np)
        # Send back the string result
        emit('scene-detection-result', {'success': True, 'predictions': result_str})
    except Exception as e:
        logger.error(f"Error in 'detect-scene' handler: {e}", exc_info=True)
        emit('scene-detection-result', {'success': False, 'error': str(e)})

@socketio.on('ocr') # Used by test.html - no change needed here as format was already string
def handle_ocr_test(data):
    logger.debug("Received 'ocr' (for test page)")
    try:
        image_data = data.get('image')
        if not image_data:
             emit('ocr-result', {'success': False, 'error': 'No image data provided'})
             return
        if ',' in image_data: header, encoded = image_data.split(',', 1)
        else: encoded = image_data
        image_bytes = base64.b64decode(encoded)
        np_array = np.frombuffer(image_bytes, np.uint8)
        image = cv2.imdecode(np_array, cv2.IMREAD_COLOR)
        if image is None:
            emit('ocr-result', {'success': False, 'error': 'Failed to decode image'})
            return
        # Call the existing function (already returns string)
        detected_text = detect_text(image)
        emit('ocr-result', {'success': True, 'detected_text': detected_text})
    except Exception as e:
        logger.error(f"Error in 'ocr' handler: {e}", exc_info=True)
        emit('ocr-result', {'success': False, 'error': str(e)})

# --- Default Error Handler ---
@socketio.on_error_default # Catch errors from any namespace
def default_error_handler(e):
    logger.error(f'Unhandled WebSocket Error: {e}', exc_info=True)
    # Attempt to inform the client if possible, but the connection might be broken
    try:
        emit('response', {'result': f'Server Error: {str(e)}'})
    except Exception as emit_err:
         logger.error(f"Failed to emit error to client during error handling: {emit_err}")


# --- HTTP Routes (Keep as is for testing/other features) ---
# ... (HTTP routes / , /update_customization, /get_user_info, /add_test_user remain the same) ...
@app.route('/')
def home():
    # Point to your test HTML file if it exists
    test_html_path = os.path.join(template_dir, 'test.html')
    if os.path.exists(test_html_path):
        return render_template('test.html')
    else:
         logger.warning("test.html not found in template folder.")
         return "Backend is running. WebSocket connections accepted. No test page found."

@app.route('/update_customization', methods=['POST'])
def update_customization():
    # (Keep your existing DB logic here)
    # ...
    try:
        data = request.json
        email = data.get('email')
        customization = data.get('customization')

        if not email or customization is None: # Allow empty string for customization
            logger.warning("Update customization request missing email or customization string.")
            return jsonify({'success': False, 'message': 'Email and customization string are required'}), 400

        # Ensure customization string is exactly 255 chars, padding with '0' if needed
        customization_padded = (customization + '0' * 255)[:255]

        with app.app_context():
            user = User.query.filter_by(email=email).first()
            if not user:
                logger.warning(f"User not found for customization update: {email}")
                return jsonify({'success': False, 'message': 'User not found'}), 404

            user.customization = customization_padded
            db.session.commit()
            logger.info(f"Customization updated successfully for user: {email}")
            return jsonify({'success': True, 'message': 'Customization updated successfully'}), 200

    except Exception as e:
        db.session.rollback() # Rollback in case of error
        logger.error(f"Error updating customization for {email if 'email' in locals() else 'unknown'}: {str(e)}", exc_info=True)
        return jsonify({'success': False, 'message': 'Internal server error during customization update'}), 500


@app.route('/get_user_info', methods=['GET'])
def get_user_info():
    # (Keep your existing DB logic here)
    # ...
    try:
        email = request.args.get('email')
        if not email:
            logger.warning("Get user info request missing email parameter.")
            return jsonify({'success': False, 'message': 'Email parameter is required'}), 400

        logger.debug(f"Attempting to retrieve user info for email: {email}")

        with app.app_context():
            user = User.query.filter_by(email=email).first()

            if not user:
                logger.warning(f"No user found with email for info retrieval: {email}")
                return jsonify({'success': False, 'message': f'No user found with email: {email}'}), 404

            logger.info(f"User info retrieved successfully for: {email}")
            return jsonify({
                'success': True,
                'name': user.name,
                'email': user.email,
                'customization': user.customization
            }), 200

    except Exception as e:
        logger.error(f"Error retrieving user info for {email if 'email' in locals() else 'unknown'}: {e}", exc_info=True)
        return jsonify({'success': False, 'message': f'Internal server error retrieving user info'}), 500

# --- Test User Route (Keep as is for testing) ---
@app.route('/add_test_user', methods=['POST'])
def add_test_user():
    # (Keep your existing DB logic here)
    # ...
    try:
        data = request.json
        name = data.get('name')
        email = data.get('email')
        password = data.get('password') # Consider hashing passwords in a real app

        if not all([name, email, password]):
            return jsonify({'success': False, 'message': 'Name, email, and password are required'}), 400

        with app.app_context():
            existing_user = User.query.filter_by(email=email).first()
            if existing_user:
                return jsonify({'success': False, 'message': 'User with this email already exists'}), 409

            # In a real app, HASH the password before saving
            # from werkzeug.security import generate_password_hash
            # hashed_password = generate_password_hash(password)
            # new_user = User(name=name, email=email, password=hashed_password)
            new_user = User(name=name, email=email, password=password) # Storing plain text for demo only

            db.session.add(new_user)
            db.session.commit()
            logger.info(f"Test user added: {name}, {email}")
            return jsonify({'success': True, 'message': 'Test user added successfully'}), 201

    except Exception as e:
        db.session.rollback()
        logger.error(f"Error adding test user: {e}", exc_info=True)
        return jsonify({'success': False, 'message': f'Error adding test user: {str(e)}'}), 500

# --- Main Execution ---
if __name__ == '__main__':
    logger.info("Starting Flask-SocketIO server...")
    # Use host='0.0.0.0' to accept connections from any IP on the network
    # Port 5000 is the target
    # Debug=True enables auto-reloading but can consume more memory; disable for production
    # Use allow_unsafe_werkzeug=True if using debug mode with recent Werkzeug versions
    socketio.run(app, debug=True, host='0.0.0.0', port=5000, use_reloader=True, allow_unsafe_werkzeug=True)
    logger.info("Server stopped.")