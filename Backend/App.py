# backend python:
# app.py

import os

# Setting this environment variable can help avoid crashes on some systems, especially macOS
os.environ["KMP_DUPLICATE_LIB_OK"] = "TRUE"

from flask import Flask, request, jsonify, render_template
from flask_cors import CORS
from flask_socketio import SocketIO, emit
from flask_sqlalchemy import SQLAlchemy
import cv2
import numpy as np
import torch
import io
import base64
import logging
from PIL import Image
import easyocr # Import easyocr
import torchvision.models as models
import torchvision.transforms as transforms
import requests
import time

# --- Logging Setup ---
logging.basicConfig(level=logging.DEBUG, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

template_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'templates'))
app = Flask(__name__, template_folder=template_dir)
CORS(app)
socketio = SocketIO(app, cors_allowed_origins="*", max_http_buffer_size=10 * 1024 * 1024, async_mode='threading')

# --- Database Setup (Keep as is) ---
# Use environment variable or default for DB URI
DB_URI = os.environ.get('DATABASE_URL', 'mysql+pymysql://root:@127.0.0.1:3306/visualaiddb')
app.config['SQLALCHEMY_DATABASE_URI'] = DB_URI
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
app.config['SQLALCHEMY_ECHO'] = False # Set to True for debugging SQL
db = SQLAlchemy(app)

def test_db_connection():
    # (Keep existing test_db_connection)
    try:
        with app.app_context():
            with db.engine.connect() as connection:
                result = connection.execute(db.text("SELECT 1"))
                logger.info("Database connection successful!")
                return True
    except Exception as e:
        logger.error(f"Database connection failed: {e}", exc_info=True)
        return False

class User(db.Model):
    # (Keep existing User model)
    __tablename__ = 'users'
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(255), nullable=False)
    email = db.Column(db.String(255), nullable=False, unique=True)
    password = db.Column(db.String(255), nullable=False)
    customization = db.Column(db.String(255), default='0' * 255)


with app.app_context():
    try:
        db.create_all()
        if not test_db_connection():
             logger.warning("Database connection failed during startup. DB features may not work.")
    except Exception as e:
        logger.error(f"Error during initial DB setup: {e}", exc_info=True)


# --- Model Loading ---
logger.info("Loading ML models...")
try:
    # YOLOv5 model
    logger.debug("Loading YOLOv5 model...")
    yolo_model = torch.hub.load('ultralytics/yolov5', 'yolov5n', device='cpu')
    logger.debug("YOLOv5 model loaded.")

    # Places365 model
    def load_places365_model():
        # (Keep existing Places365 loading logic)
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
                raise # Re-raise to prevent server start if model is crucial
        else:
             logger.debug(f"Found existing Places365 weights at {weights_path}.")

        try:
            checkpoint = torch.load(weights_path, map_location='cpu')
            state_dict = checkpoint.get('state_dict', checkpoint)
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
        # Use a cached file or download if needed
        labels_url = 'https://raw.githubusercontent.com/csailvision/places365/master/categories_places365.txt'
        labels_file = 'categories_places365.txt'
        if not os.path.exists(labels_file):
             response = requests.get(labels_url, timeout=10)
             response.raise_for_status()
             with open(labels_file, 'w') as f:
                 f.write(response.text)
             logger.info("Downloaded Places365 labels.")
        else:
             logger.debug("Using cached Places365 labels.")

        with open(labels_file, 'r') as f:
            for line in f:
                if line.strip():
                    parts = line.strip().split(' ')
                    label = parts[0].split('/')[-1]
                    places_labels.append(label)
        logger.debug(f"Loaded {len(places_labels)} Places365 labels.")
    except requests.exceptions.RequestException as req_e:
        logger.error(f"Failed to download/load Places365 labels: {req_e}")
        places_labels = [f"Label {i}" for i in range(365)] # Fallback
    except IOError as io_e:
        logger.error(f"Failed to read Places365 labels file: {io_e}")
        places_labels = [f"Label {i}" for i in range(365)] # Fallback


    # *** MODIFIED: EasyOCR Reader Initialization ***
    # Define supported languages and default
    SUPPORTED_OCR_LANGS = ['en', 'es', 'fr'] # Match codes used in Flutter app
    DEFAULT_OCR_LANG = 'en'
    logger.info(f"Supported OCR languages: {SUPPORTED_OCR_LANGS}")

    # Create a dictionary to hold reader instances for each language
    ocr_readers = {}
    for lang_code in SUPPORTED_OCR_LANGS:
        try:
            logger.debug(f"Loading EasyOCR reader for language: '{lang_code}'...")
            # Initialize reader for ONE language at a time
            ocr_readers[lang_code] = easyocr.Reader([lang_code], gpu=False, verbose=False)
            logger.debug(f"EasyOCR reader for '{lang_code}' loaded.")
        except Exception as ocr_load_e:
             logger.error(f"Failed to load EasyOCR reader for language '{lang_code}': {ocr_load_e}", exc_info=True)
             # Decide how to handle failure: continue without this language, or stop?
             # For now, we log the error and continue; requests for this lang will fail later.

    if DEFAULT_OCR_LANG not in ocr_readers:
        logger.error(f"Default OCR language '{DEFAULT_OCR_LANG}' failed to load! Text detection may fail.")
        # Consider raising SystemExit if the default is critical

    logger.info("EasyOCR readers loaded.")


    # Image transforms for scene detection
    scene_transform = transforms.Compose([
        transforms.Resize((256, 256)),
        transforms.CenterCrop(224),
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
    ])

    logger.info("All ML models loaded successfully (or with noted exceptions).")

except Exception as e:
    logger.error(f"FATAL ERROR DURING MODEL LOADING: {e}", exc_info=True)
    raise SystemExit(f"Failed to load critical ML models: {e}")


# --- Detection Functions ---

def detect_objects(image_np):
    """Perform object detection using YOLOv5"""
    logger.debug("Starting object detection...")
    try:
        # Convert BGR (cv2 default) to RGB
        img_rgb = cv2.cvtColor(image_np, cv2.COLOR_BGR2RGB)
        img_pil = Image.fromarray(img_rgb)

        results = yolo_model(img_pil)
        detections = results.pandas().xyxy[0]
        filtered_detections = detections[detections['confidence'] > 0.4]

        object_list = [row['name'] for _, row in filtered_detections.iterrows()]

        if not object_list:
            # logger.debug("Object detection: No objects found.") # Less verbose
            return "No objects detected"
        else:
            result_str = ", ".join(object_list)
            logger.debug(f"Object detection complete: {result_str}")
            return result_str
    except Exception as e:
        logger.error(f"Error during object detection: {e}", exc_info=True)
        return "Error in object detection"

def detect_scene(image_np):
    """Perform scene classification using Places365"""
    logger.debug("Starting scene detection...")
    try:
        # Convert BGR to RGB
        img_rgb = cv2.cvtColor(image_np, cv2.COLOR_BGR2RGB)
        img_pil = Image.fromarray(img_rgb)
        img_tensor = scene_transform(img_pil).unsqueeze(0)

        with torch.no_grad():
            outputs = places_model(img_tensor)
            probabilities = torch.softmax(outputs, dim=1)[0]
            top_prob, top_catid = torch.max(probabilities, 0)

            # Ensure the index is within the bounds of the loaded labels
            if top_catid.item() < len(places_labels):
                predicted_label = places_labels[top_catid.item()]
            else:
                 logger.warning(f"Predicted category ID {top_catid.item()} out of bounds for labels list (length {len(places_labels)}).")
                 predicted_label = "Unknown Scene"

        result_str = f"{predicted_label}"
        logger.debug(f"Scene detection complete: {result_str}")
        return result_str
    except Exception as e:
        logger.error(f"Error during scene detection: {e}", exc_info=True)
        return "Error in scene detection"

# *** MODIFIED: Accepts language code and uses specific reader ***
def detect_text(image_np, language_code=DEFAULT_OCR_LANG):
    """Perform text detection using the EasyOCR reader for the specified language."""
    logger.debug(f"Starting text detection for language: '{language_code}'...")

    # Validate requested language and get the corresponding reader
    reader = ocr_readers.get(language_code)
    if reader is None:
        logger.warning(f"Unsupported or unloaded language '{language_code}' requested. Falling back to '{DEFAULT_OCR_LANG}'.")
        reader = ocr_readers.get(DEFAULT_OCR_LANG)
        # If even the default reader failed to load, we have a problem
        if reader is None:
             logger.error(f"Default OCR reader ('{DEFAULT_OCR_LANG}') is not available. Cannot perform OCR.")
             return f"Error: OCR language '{language_code}' not available"

    try:
        # Perform OCR using the selected reader
        # detail=0 returns only the text, not bounding boxes or confidence
        results = reader.readtext(image_np, detail=0, paragraph=True) # Group text into paragraphs

        if not results:
            # logger.debug(f"Text detection ({language_code}): No text found.") # Less verbose
            return "No text detected"
        else:
            # Join paragraph results with newlines for better readability
            result_str = "\n".join(results)
            logger.debug(f"Text detection ({language_code}) complete: Found text '{result_str[:100].replace('\n', ' ')}...'")
            return result_str
    except Exception as e:
        logger.error(f"Error during text detection ({language_code}): {e}", exc_info=True)
        return f"Error during text detection ({language_code})"


# --- WebSocket Handlers ---
@socketio.on('connect')
def handle_connect():
    logger.info(f'Client connected: {request.sid}')
    emit('response', {'result': 'Connected to VisionAid backend', 'event': 'connect'}) # Echo connect event

@socketio.on('disconnect')
def handle_disconnect():
     logger.info(f'Client disconnected: {request.sid}')

@socketio.on('message')
def handle_message(data):
    client_sid = request.sid
    start_time = time.time()

    try:
        # 1. Validate input data structure
        if not isinstance(data, dict):
            logger.warning(f"Invalid data format from {client_sid}. Expected dict, got {type(data)}.")
            emit('response', {'result': 'Error: Invalid data format'})
            return

        image_data = data.get('image')
        detection_type = data.get('type')
        # *** NEW: Get requested language, default to English if not provided ***
        requested_language = data.get('language', DEFAULT_OCR_LANG).lower() # Get language, default, lowercase

        if not image_data or not detection_type:
            logger.warning(f"Missing 'image' or 'type' field from {client_sid}.")
            emit('response', {'result': "Error: Missing 'image' or 'type'"})
            return

        logger.info(f"Processing request from {client_sid}. Type: '{detection_type}'" +
                    (f", Lang: '{requested_language}'" if detection_type == 'text_detection' else ""))

        # 2. Decode Base64 Image
        try:
            # *** FIXED SYNTAX HERE ***
            if ',' in image_data:
                _, encoded = image_data.split(',', 1)
            else:
                encoded = image_data

            image_bytes = base64.b64decode(encoded)
            # Use cv2.imdecode for robustness
            image_np = cv2.imdecode(np.frombuffer(image_bytes, np.uint8), cv2.IMREAD_COLOR)
            if image_np is None: raise ValueError("Failed to decode image using cv2.imdecode")
            # logger.debug(f"Image decoded successfully from {client_sid}. Shape: {image_np.shape}") # Less verbose

        except (base64.binascii.Error, ValueError) as b64e:
            logger.error(f"Image decoding error for {client_sid}: {b64e}")
            emit('response', {'result': 'Error: Invalid or corrupt image data'})
            return
        except Exception as decode_e:
             logger.error(f"Unexpected error decoding image for {client_sid}: {decode_e}", exc_info=True)
             emit('response', {'result': 'Error: Could not process image'})
             return

        # 3. Process Image based on detection type
        result = "Error: Unknown processing error" # Default error
        if detection_type == 'object_detection':
            result = detect_objects(image_np)
        elif detection_type == 'scene_detection':
            result = detect_scene(image_np)
        elif detection_type == 'text_detection':
            # *** MODIFIED: Pass the requested language code ***
            result = detect_text(image_np, language_code=requested_language)
        else:
            logger.warning(f"Received unsupported detection type '{detection_type}' from {client_sid}")
            result = "Error: Unsupported detection type"

        processing_time = time.time() - start_time
        logger.info(f"Completed {detection_type} for {client_sid} in {processing_time:.3f}s. Result: '{str(result)[:100].replace('\n', ' ')}...'")

        # 4. Emit result back
        emit('response', {'result': result}) # Send only the result string as per current Flutter expectation

    except Exception as e:
        processing_time = time.time() - start_time
        logger.error(f"Unhandled error processing '{data.get('type', 'unknown')}' request for {client_sid} after {processing_time:.3f}s: {e}", exc_info=True)
        try:
            emit('response', {'result': f'Server Error: An unexpected error occurred.'})
        except Exception as emit_e:
            logger.error(f"Failed to emit error response to {client_sid}: {emit_e}")


# --- Test page handlers (updated for consistency if needed) ---
# Keep test handlers, but they won't use the language feature unless modified
# ... (Keep test handlers: handle_object_detection_test, handle_scene_detection_test) ...
@socketio.on('detect-objects') # Used by test.html
def handle_object_detection_test(data):
    logger.debug("Received 'detect-objects' (for test page)")
    try:
        img_data = data.get('image')
        if not img_data: emit('object-detection-result', {'success': False, 'error': 'No image data'}); return

        # *** FIXED SYNTAX HERE ***
        if ',' in img_data:
            _, encoded = img_data.split(',', 1)
        else:
            encoded = img_data

        img_bytes = base64.b64decode(encoded)
        image_np = cv2.imdecode(np.frombuffer(img_bytes, np.uint8), cv2.IMREAD_COLOR)
        if image_np is None: raise ValueError("Failed to decode image")
        result_str = detect_objects(image_np)
        emit('object-detection-result', {'success': True, 'detections': result_str}) # Mimic app response
    except Exception as e:
        logger.error(f"Error in 'detect-objects' handler: {e}", exc_info=True)
        emit('object-detection-result', {'success': False, 'error': str(e)})

@socketio.on('detect-scene') # Used by test.html
def handle_scene_detection_test(data):
    logger.debug("Received 'detect-scene' (for test page)")
    try:
        img_data = data.get('image')
        if not img_data: emit('scene-detection-result', {'success': False, 'error': 'No image data'}); return

        # *** FIXED SYNTAX HERE ***
        if ',' in img_data:
            _, encoded = img_data.split(',', 1)
        else:
            encoded = img_data

        img_bytes = base64.b64decode(encoded)
        image_np = cv2.imdecode(np.frombuffer(img_bytes, np.uint8), cv2.IMREAD_COLOR)
        if image_np is None: raise ValueError("Failed to decode image")
        result_str = detect_scene(image_np)
        emit('scene-detection-result', {'success': True, 'predictions': result_str}) # Mimic app response
    except Exception as e:
        logger.error(f"Error in 'detect-scene' handler: {e}", exc_info=True)
        emit('scene-detection-result', {'success': False, 'error': str(e)})

# *** MODIFIED: Test handler for OCR now uses default language ***
@socketio.on('ocr') # Used by test.html
def handle_ocr_test(data):
    logger.debug("Received 'ocr' (for test page)")
    try:
        image_data = data.get('image')
        if not image_data: emit('ocr-result', {'success': False, 'error': 'No image data'}); return

        # *** FIXED SYNTAX HERE ***
        if ',' in image_data:
            _, encoded = image_data.split(',', 1)
        else:
            encoded = image_data

        image_bytes = base64.b64decode(encoded)
        image_np = cv2.imdecode(np.frombuffer(image_bytes, np.uint8), cv2.IMREAD_COLOR)
        if image_np is None: raise ValueError("Failed to decode image")
        # Call detect_text, which now uses the default reader if no language specified
        detected_text = detect_text(image_np) # Uses DEFAULT_OCR_LANG
        emit('ocr-result', {'success': True, 'detected_text': detected_text}) # Mimic app response
    except Exception as e:
        logger.error(f"Error in 'ocr' handler: {e}", exc_info=True)
        emit('ocr-result', {'success': False, 'error': str(e)})


# --- Default Error Handler ---
@socketio.on_error_default
def default_error_handler(e):
    logger.error(f'Unhandled WebSocket Error: {e}', exc_info=True)
    try:
        # Be careful emitting here, the connection might be compromised
        # Check if request namespace exists before emitting
        if hasattr(request, 'namespace') and request.namespace:
             request.namespace.emit('response', {'result': f'Server Error: {str(e)}'})
        else:
             logger.warning("Cannot emit error response: No request namespace found.")
    except Exception as emit_err:
         logger.error(f"Failed to emit error during default error handling: {emit_err}")


# --- HTTP Routes (Keep as is for testing/other features) ---
# ... (Keep routes: / , /update_customization, /get_user_info, /add_test_user) ...
@app.route('/')
def home():
    test_html_path = os.path.join(template_dir, 'test.html')
    if os.path.exists(test_html_path):
        return render_template('test.html')
    else:
         logger.warning("test.html not found in template folder.")
         return "Backend is running. WebSocket connections accepted. Add test.html to templates/ for a test interface."

@app.route('/update_customization', methods=['POST'])
def update_customization():
    # (Keep existing DB logic)
    try:
        data = request.json
        email = data.get('email')
        customization = data.get('customization')
        if not email or customization is None:
            return jsonify({'success': False, 'message': 'Email and customization required'}), 400
        customization_padded = (customization + '0' * 255)[:255]
        with app.app_context():
            user = User.query.filter_by(email=email).first()
            if not user: return jsonify({'success': False, 'message': 'User not found'}), 404
            user.customization = customization_padded
            db.session.commit()
            logger.info(f"Customization updated for user: {email}")
            return jsonify({'success': True, 'message': 'Customization updated'}), 200
    except Exception as e:
        db.session.rollback()
        logger.error(f"Error updating customization: {e}", exc_info=True)
        return jsonify({'success': False, 'message': 'Internal server error'}), 500


@app.route('/get_user_info', methods=['GET'])
def get_user_info():
    # (Keep existing DB logic)
    try:
        email = request.args.get('email')
        if not email: return jsonify({'success': False, 'message': 'Email parameter required'}), 400
        with app.app_context():
            user = User.query.filter_by(email=email).first()
            if not user: return jsonify({'success': False, 'message': 'User not found'}), 404
            logger.info(f"User info retrieved for: {email}")
            return jsonify({'success': True, 'name': user.name, 'email': user.email, 'customization': user.customization}), 200
    except Exception as e:
        logger.error(f"Error retrieving user info: {e}", exc_info=True)
        return jsonify({'success': False, 'message': 'Internal server error'}), 500


@app.route('/add_test_user', methods=['POST'])
def add_test_user():
    # (Keep existing DB logic - remember to hash passwords in production)
    try:
        data = request.json
        name = data.get('name')
        email = data.get('email')
        password = data.get('password') # HASH THIS IN PRODUCTION
        if not all([name, email, password]):
            return jsonify({'success': False, 'message': 'Missing fields'}), 400
        with app.app_context():
            if User.query.filter_by(email=email).first():
                return jsonify({'success': False, 'message': 'Email already exists'}), 409
            new_user = User(name=name, email=email, password=password) # Store plain text demo
            db.session.add(new_user)
            db.session.commit()
            logger.info(f"Test user added: {email}")
            return jsonify({'success': True, 'message': 'Test user added'}), 201
    except Exception as e:
        db.session.rollback()
        logger.error(f"Error adding test user: {e}", exc_info=True)
        return jsonify({'success': False, 'message': 'Internal server error'}), 500


# --- Main Execution ---
if __name__ == '__main__':
    logger.info("Starting Flask-SocketIO server...")
    # Use host='0.0.0.0' to be accessible on the network
    # Set debug=False and use_reloader=False for production
    # allow_unsafe_werkzeug=True only needed if debug=True with newer Werkzeug
    try:
        socketio.run(app,
                    debug=True, # Set to False for production
                    host='0.0.0.0',
                    port=5000,
                    use_reloader=True, # Set to False for production
                    allow_unsafe_werkzeug=True # Needed for reloader in debug mode
                    )
    except Exception as run_e:
        logger.critical(f"Failed to start the server: {run_e}", exc_info=True)
    finally:
         logger.info("Server shutdown.")