import os

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
import pytesseract # Replaced easyocr
import torchvision.models as models
import torchvision.transforms as transforms
import requests
import time
import sys

logging.basicConfig(level=logging.INFO,
                    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

template_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'templates'))
app = Flask(__name__, template_folder=template_dir)
CORS(app)
socketio = SocketIO(app, cors_allowed_origins="*", max_http_buffer_size=10 * 1024 * 1024, async_mode='threading')


# --- Tesseract Configuration (MODIFY IF NEEDED) ---
try:
    # Attempt to find Tesseract automatically. If this fails, uncomment
    # and set the path below appropriate for your system.
    # Example for Windows:
    # pytesseract.pytesseract.tesseract_cmd = r'C:\Program Files\Tesseract-OCR\tesseract.exe'
    # Example for Linux (if not in PATH):
    # pytesseract.pytesseract.tesseract_cmd = r'/usr/bin/tesseract'
    # Example for macOS (if installed via brew but not found):
    # pytesseract.pytesseract.tesseract_cmd = r'/opt/homebrew/bin/tesseract' # Apple Silicon
    # pytesseract.pytesseract.tesseract_cmd = r'/usr/local/bin/tesseract' # Intel Macs

    # Check if command can be found (optional but good practice)
    tesseract_version = pytesseract.get_tesseract_version()
    logger.info(f"Tesseract OCR Engine found automatically. Version: {tesseract_version}")
except pytesseract.TesseractNotFoundError:
    logger.error("TesseractNotFoundError: Tesseract is not installed or not in your PATH.")
    logger.error("Please install Tesseract OCR and ensure it's in your PATH, or set pytesseract.tesseract_cmd explicitly.")
    # Optionally exit if Tesseract is critical:
    # sys.exit("Tesseract OCR not found. Backend cannot start.")
except Exception as e:
     logger.error(f"Error configuring Tesseract path or getting version: {e}")



DB_URI = os.environ.get('DATABASE_URL', 'mysql+pymysql://root:@127.0.0.1:3306/visualaiddb')
app.config['SQLALCHEMY_DATABASE_URI'] = DB_URI
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
app.config['SQLALCHEMY_ECHO'] = False
db = SQLAlchemy(app)

def test_db_connection():
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


logger.info("Loading ML models...")
try:

    logger.info("Loading YOLOv5 model...")
    yolo_model = torch.hub.load('ultralytics/yolov5', 'yolov5n', device='cpu')
    logger.info("YOLOv5 model loaded.")


    def load_places365_model():
        logger.info("Loading Places365 model...")
        model = models.resnet50(weights=None)
        model.fc = torch.nn.Linear(model.fc.in_features, 365)
        weights_path = 'resnet50_places365.pth.tar'

        if not os.path.exists(weights_path):
            logger.info(f"Downloading Places365 weights to {weights_path}...")
            try:
                response = requests.get('http://places2.csail.mit.edu/models_places365/resnet50_places365.pth.tar', timeout=60)
                response.raise_for_status()
                with open(weights_path, 'wb') as f: f.write(response.content)
                logger.info("Places365 weights downloaded.")
            except requests.exceptions.RequestException as req_e:
                logger.error(f"Failed to download Places365 weights: {req_e}")
                raise
        else: logger.debug(f"Found existing Places365 weights at {weights_path}.")
        try:
            checkpoint = torch.load(weights_path, map_location='cpu')
            state_dict = checkpoint.get('state_dict', checkpoint)
            state_dict = {k.replace('module.', ''): v for k, v in state_dict.items()}
            model.load_state_dict(state_dict)
            logger.info("Places365 model weights loaded successfully.")
            return model.eval()
        except Exception as load_e:
            logger.error(f"Error loading Places365 weights from file: {load_e}", exc_info=True)
            raise

    places_model = load_places365_model()


    logger.info("Loading Places365 labels...")
    places_labels = []
    try:

        labels_url = 'https://raw.githubusercontent.com/csailvision/places365/master/categories_places365.txt'
        labels_file = 'categories_places365.txt'
        if not os.path.exists(labels_file):
             response = requests.get(labels_url, timeout=15)
             response.raise_for_status()
             with open(labels_file, 'w', encoding='utf-8') as f: f.write(response.text)
             logger.info("Downloaded Places365 labels.")
        else: logger.debug("Using cached Places365 labels.")
        with open(labels_file, 'r', encoding='utf-8') as f:
            for line in f:
                if line.strip():
                    parts = line.strip().split(' ')
                    label = parts[0].split('/')[-1]
                    places_labels.append(label)
        logger.info(f"Loaded {len(places_labels)} Places365 labels.")
    except Exception as e:
        logger.error(f"Failed to load Places365 labels: {e}", exc_info=True)
        places_labels = [f"Label {i}" for i in range(365)]

    # --- Tesseract Supported Languages (Use Tesseract codes - 3 letters usually) ---
    # Note: You MUST have installed the corresponding tesseract-ocr-[lang] package
    #       on your system for these languages to work.
    # This list now drives validation. The frontend MUST send codes from this list.
    # Consider updating frontend's SettingsService accordingly.
    SUPPORTED_OCR_LANGS = {
        'eng', # English
        'ara', # Arabic
        'fas', # Persian (Farsi)
        'urd', # Urdu
        'uig', # Uyghur
        'hin', # Hindi
        'mar', # Marathi
        'nep', # Nepali
        'rus', # Russian
        'chi_sim', # Chinese Simplified
        'chi_tra', # Chinese Traditional
        'jpn', # Japanese
        'kor', # Korean
        'tel', # Telugu
        'kan', # Kannada
        'ben', # Bengali
        # Add other Tesseract language codes (e.g., 'fra', 'deu', 'spa') if needed
        # AND ensure the corresponding language packs are installed.
    }
    DEFAULT_OCR_LANG = 'eng' # Default Tesseract language code
    logger.info(f"Tesseract OCR configured. Supported languages (if installed): {SUPPORTED_OCR_LANGS}")
    logger.info(f"Default Tesseract OCR language: {DEFAULT_OCR_LANG}")

    # --- Image Transforms ---
    scene_transform = transforms.Compose([
        transforms.Resize((256, 256)),
        transforms.CenterCrop(224),
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
    ])

    logger.info("Base ML models loaded successfully.")

except SystemExit as se:
    logger.critical(str(se))
    sys.exit(1)
except Exception as e:
    logger.critical(f"FATAL ERROR DURING MODEL LOADING: {e}", exc_info=True)
    sys.exit(f"Failed to load critical ML models: {e}")


# --- Detection Functions ---

def detect_objects(image_np):
    try:
        img_rgb = cv2.cvtColor(image_np, cv2.COLOR_BGR2RGB)
        img_pil = Image.fromarray(img_rgb)
        results = yolo_model(img_pil)
        detections = results.pandas().xyxy[0]
        filtered_detections = detections[detections['confidence'] > 0.4]
        object_list = [row['name'] for _, row in filtered_detections.iterrows()]
        if not object_list: return "No objects detected"
        else:
            result_str = ", ".join(object_list)
            logger.debug(f"Object detection complete: {result_str}")
            return result_str
    except Exception as e:
        logger.error(f"Error during object detection: {e}", exc_info=True)
        return "Error in object detection"

def detect_scene(image_np):
    try:
        img_rgb = cv2.cvtColor(image_np, cv2.COLOR_BGR2RGB)
        img_pil = Image.fromarray(img_rgb)
        img_tensor = scene_transform(img_pil).unsqueeze(0)
        with torch.no_grad():
            outputs = places_model(img_tensor)
            probabilities = torch.softmax(outputs, dim=1)[0]
            _, top_catid = torch.max(probabilities, 0)
            if top_catid.item() < len(places_labels): predicted_label = places_labels[top_catid.item()]
            else:
                 logger.warning(f"Predicted category ID {top_catid.item()} out of bounds for labels list (length {len(places_labels)}).")
                 predicted_label = "Unknown Scene"
        result_str = f"{predicted_label}"
        logger.debug(f"Scene detection complete: {result_str}")
        return result_str
    except Exception as e:
        logger.error(f"Error during scene detection: {e}", exc_info=True)
        return "Error in scene detection"


def detect_text(image_np, language_code=DEFAULT_OCR_LANG):
    """Perform text detection using Tesseract OCR."""
    logger.debug(f"Starting Tesseract text detection for language: '{language_code}'...")

    # Validate language code against our supported list
    # Tesseract itself might support more if installed, but we limit to configured ones
    validated_lang = language_code if language_code in SUPPORTED_OCR_LANGS else DEFAULT_OCR_LANG
    if validated_lang != language_code:
        logger.warning(f"Requested language '{language_code}' not in supported list. Falling back to '{DEFAULT_OCR_LANG}'.")

    try:
        # Convert OpenCV image (BGR) to PIL image (RGB) which pytesseract prefers
        img_rgb = cv2.cvtColor(image_np, cv2.COLOR_BGR2RGB)
        img_pil = Image.fromarray(img_rgb)

        # Use pytesseract to get string
        # Add config options if needed, e.g., --psm 6 for assuming a single uniform block of text
        # config = '--psm 6'
        detected_text = pytesseract.image_to_string(img_pil, lang=validated_lang) # , config=config

        result_str = detected_text.strip() # Remove leading/trailing whitespace

        if not result_str:
            logger.debug(f"Tesseract ({validated_lang}): No text found.")
            return "No text detected"
        else:
            logger.debug(f"Tesseract ({validated_lang}) complete: Found text '{result_str[:100].replace('\n', ' ')}...'")
            return result_str
    except pytesseract.TesseractNotFoundError:
        logger.error("TesseractNotFoundError: Tesseract executable not found. Check installation and path.")
        return "Error: OCR Engine Not Found"
    except pytesseract.TesseractError as tess_e:
        # This might happen if the language pack is missing or there's another Tesseract issue
        logger.error(f"TesseractError during text detection ({validated_lang}): {tess_e}", exc_info=False)
        # Check if it's likely a missing language pack error
        if "Failed loading language" in str(tess_e) or "Data path" in str(tess_e):
             logger.warning(f"Potential missing language pack for '{validated_lang}'. Please install tesseract-ocr-{validated_lang}.")
             # Fallback to English if the requested language failed
             if validated_lang != DEFAULT_OCR_LANG:
                 logger.warning(f"Attempting fallback OCR with default language '{DEFAULT_OCR_LANG}'...")
                 try:
                    img_rgb = cv2.cvtColor(image_np, cv2.COLOR_BGR2RGB)
                    img_pil = Image.fromarray(img_rgb)
                    fallback_text = pytesseract.image_to_string(img_pil, lang=DEFAULT_OCR_LANG)
                    fallback_result = fallback_text.strip()
                    if not fallback_result: return "No text detected (fallback)"
                    else: return fallback_result
                 except Exception as fallback_e:
                      logger.error(f"Error during fallback OCR ({DEFAULT_OCR_LANG}): {fallback_e}")
                      return f"Error during OCR fallback"
             else:
                 return f"Error: OCR failed for '{validated_lang}' (Missing language pack?)"
        else:
            return f"Error during text detection ({validated_lang})"
    except Exception as e:
        logger.error(f"Unexpected error during Tesseract text detection ({validated_lang}): {e}", exc_info=True)
        return f"Error during text detection ({validated_lang})"


# --- WebSocket Handlers ---
@socketio.on('connect')
def handle_connect():
    logger.info(f'Client connected: {request.sid}')
    emit('response', {'result': 'Connected to VisionAid backend', 'event': 'connect'})

@socketio.on('disconnect')
def handle_disconnect():
     logger.info(f'Client disconnected: {request.sid}')

@socketio.on('message')
def handle_message(data):
    client_sid = request.sid
    start_time = time.time()
    try:
        if not isinstance(data, dict):
            logger.warning(f"Invalid data format from {client_sid}. Expected dict, got {type(data)}.")
            emit('response', {'result': 'Error: Invalid data format'}); return

        image_data = data.get('image')
        detection_type = data.get('type')


        requested_language = DEFAULT_OCR_LANG # Default unless specified for text
        if detection_type == 'text_detection':
            # Get requested language from payload, convert to lowercase Tesseract code
            # Assuming frontend sends Tesseract codes now (e.g., 'eng', 'ara')
            requested_language_from_payload = data.get('language', DEFAULT_OCR_LANG).lower()
            # Validate against loaded languages (keys of SUPPORTED_OCR_LANGS set)
            if requested_language_from_payload not in SUPPORTED_OCR_LANGS:
                 logger.warning(f"Client requested unsupported/unloaded language '{requested_language_from_payload}', falling back to '{DEFAULT_OCR_LANG}'.")
                 requested_language = DEFAULT_OCR_LANG
            else:
                requested_language = requested_language_from_payload


        if not image_data or not detection_type:
            logger.warning(f"Missing 'image' or 'type' field from {client_sid}.")
            emit('response', {'result': "Error: Missing 'image' or 'type'"}); return

        logger.info(f"Processing request from {client_sid}. Type: '{detection_type}'" +
                    (f", Lang: '{requested_language}'" if detection_type == 'text_detection' else ""))


        try:
            if ',' in image_data: _, encoded = image_data.split(',', 1)
            else: encoded = image_data
            image_bytes = base64.b64decode(encoded)
            image_np = cv2.imdecode(np.frombuffer(image_bytes, np.uint8), cv2.IMREAD_COLOR)
            if image_np is None: raise ValueError("Failed to decode image using cv2.imdecode")
        except (base64.binascii.Error, ValueError) as b64e:
            logger.error(f"Image decoding error for {client_sid}: {b64e}")
            emit('response', {'result': 'Error: Invalid or corrupt image data'}); return
        except Exception as decode_e:
             logger.error(f"Unexpected error decoding image for {client_sid}: {decode_e}", exc_info=True)
             emit('response', {'result': 'Error: Could not process image'}); return


        result = "Error: Unknown processing error"
        if detection_type == 'object_detection': result = detect_objects(image_np)
        elif detection_type == 'scene_detection': result = detect_scene(image_np)
        elif detection_type == 'text_detection': result = detect_text(image_np, language_code=requested_language)
        else:
            logger.warning(f"Received unsupported detection type '{detection_type}' from {client_sid}")
            result = "Error: Unsupported detection type"

        processing_time = time.time() - start_time
        logger.info(f"Completed {detection_type} for {client_sid} in {processing_time:.3f}s. Result: '{str(result)[:100].replace('\n', ' ')}...'")


        emit('response', {'result': result})

    except Exception as e:
        processing_time = time.time() - start_time
        logger.error(f"Unhandled error processing '{data.get('type', 'unknown')}' request for {client_sid} after {processing_time:.3f}s: {e}", exc_info=True)
        try: emit('response', {'result': f'Server Error: An unexpected error occurred.'})
        except Exception as emit_e: logger.error(f"Failed to emit error response to {client_sid}: {emit_e}")


# --- Test page handlers (Kept for basic testing) ---
@socketio.on('detect-objects')
def handle_object_detection_test(data):
    logger.debug("Received 'detect-objects' (for test page)")
    try:
        img_data = data.get('image');
        if not img_data: emit('object-detection-result', {'success': False, 'error': 'No image data'}); return
        if ',' in img_data: _, encoded = img_data.split(',', 1)
        else: encoded = img_data
        img_bytes = base64.b64decode(encoded)
        image_np = cv2.imdecode(np.frombuffer(img_bytes, np.uint8), cv2.IMREAD_COLOR)
        if image_np is None: raise ValueError("Failed to decode image")
        result_str = detect_objects(image_np)
        emit('object-detection-result', {'success': True, 'detections': result_str})
    except Exception as e: logger.error(f"Error in 'detect-objects' handler: {e}", exc_info=True); emit('object-detection-result', {'success': False, 'error': str(e)})

@socketio.on('detect-scene')
def handle_scene_detection_test(data):
    logger.debug("Received 'detect-scene' (for test page)")
    try:
        img_data = data.get('image');
        if not img_data: emit('scene-detection-result', {'success': False, 'error': 'No image data'}); return
        if ',' in img_data: _, encoded = img_data.split(',', 1)
        else: encoded = img_data
        img_bytes = base64.b64decode(encoded)
        image_np = cv2.imdecode(np.frombuffer(img_bytes, np.uint8), cv2.IMREAD_COLOR)
        if image_np is None: raise ValueError("Failed to decode image")
        result_str = detect_scene(image_np)
        emit('scene-detection-result', {'success': True, 'predictions': result_str})
    except Exception as e: logger.error(f"Error in 'detect-scene' handler: {e}", exc_info=True); emit('scene-detection-result', {'success': False, 'error': str(e)})

@socketio.on('ocr')
def handle_ocr_test(data):
    logger.debug("Received 'ocr' (for test page - uses default lang 'eng')")
    try:
        img_data = data.get('image');
        if not img_data: emit('ocr-result', {'success': False, 'error': 'No image data'}); return
        if ',' in img_data: _, encoded = img_data.split(',', 1)
        else: encoded = img_data
        img_bytes = base64.b64decode(encoded)
        image_np = cv2.imdecode(np.frombuffer(img_bytes, np.uint8), cv2.IMREAD_COLOR)
        if image_np is None: raise ValueError("Failed to decode image")
        detected_text = detect_text(image_np, language_code=DEFAULT_OCR_LANG) # Uses default
        emit('ocr-result', {'success': True, 'detected_text': detected_text})
    except Exception as e: logger.error(f"Error in 'ocr' handler: {e}", exc_info=True); emit('ocr-result', {'success': False, 'error': str(e)})


# --- Default Error Handler ---
@socketio.on_error_default
def default_error_handler(e):
    logger.error(f'Unhandled WebSocket Error: {e}', exc_info=True)

    try:
        emit('response', {'result': f'Server Error: An internal error occurred.'})
    except Exception as emit_err:
        logger.error(f"Failed to emit error during default error handling: {emit_err}")


# --- HTTP Routes (Keep existing) ---
@app.route('/')
def home():

    test_html_path = os.path.join(template_dir, 'test.html')
    if os.path.exists(test_html_path): return render_template('test.html')
    else: logger.warning("test.html not found in template folder."); return "Backend is running. WebSocket OK."


@app.route('/update_customization', methods=['POST'])
def update_customization():
    try:
        data = request.json; email = data.get('email'); customization = data.get('customization')
        if not email or customization is None: return jsonify({'success': False, 'message': 'Email and customization required'}), 400
        customization_padded = (customization + '0' * 255)[:255]
        with app.app_context():
            user = User.query.filter_by(email=email).first()
            if not user: return jsonify({'success': False, 'message': 'User not found'}), 404
            user.customization = customization_padded; db.session.commit()
            logger.info(f"Customization updated for user: {email}")
            return jsonify({'success': True, 'message': 'Customization updated'}), 200
    except Exception as e: db.session.rollback(); logger.error(f"Error updating customization: {e}", exc_info=True); return jsonify({'success': False, 'message': 'Internal server error'}), 500

@app.route('/get_user_info', methods=['GET'])
def get_user_info():
    try:
        email = request.args.get('email');
        if not email: return jsonify({'success': False, 'message': 'Email parameter required'}), 400
        with app.app_context():
            user = User.query.filter_by(email=email).first()
            if not user: return jsonify({'success': False, 'message': 'User not found'}), 404
            logger.info(f"User info retrieved for: {email}")
            return jsonify({'success': True, 'name': user.name, 'email': user.email, 'customization': user.customization}), 200
    except Exception as e: logger.error(f"Error retrieving user info: {e}", exc_info=True); return jsonify({'success': False, 'message': 'Internal server error'}), 500

@app.route('/add_test_user', methods=['POST'])
def add_test_user():
    try:
        data = request.json; name = data.get('name'); email = data.get('email'); password = data.get('password')
        if not all([name, email, password]): return jsonify({'success': False, 'message': 'Missing fields'}), 400
        with app.app_context():
            if User.query.filter_by(email=email).first(): return jsonify({'success': False, 'message': 'Email already exists'}), 409

            new_user = User(name=name, email=email, password=password); db.session.add(new_user); db.session.commit()
            logger.info(f"Test user added: {email}")
            return jsonify({'success': True, 'message': 'Test user added'}), 201
    except Exception as e: db.session.rollback(); logger.error(f"Error adding test user: {e}", exc_info=True); return jsonify({'success': False, 'message': 'Internal server error'}), 500


# --- Main Execution ---
if __name__ == '__main__':
    logger.info("Starting Flask-SocketIO server...")

    host_ip = '0.0.0.0'
    port_num = 5000
    logger.info(f"Server will listen on {host_ip}:{port_num}")
    try:
        socketio.run(app,
                    debug=True,
                    host=host_ip,
                    port=port_num,
                    use_reloader=True,
                    allow_unsafe_werkzeug=True
                    )
    except Exception as run_e:
        logger.critical(f"Failed to start the server: {run_e}", exc_info=True)
    finally:
         logger.info("Server shutdown.")