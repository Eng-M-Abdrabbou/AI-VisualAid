# backend/app.py

import os

os.environ["KMP_DUPLICATE_LIB_OK"] = "TRUE" # Keep if needed

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
import pytesseract # For OCR
import torchvision.models as models # For Places365
import torchvision.transforms as transforms # For Places365
import requests
import time
import sys
from ultralytics import YOLO # Using YOLO from ultralytics for YOLO-World

logging.basicConfig(level=logging.INFO,
                    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

template_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'templates'))
app = Flask(__name__, template_folder=template_dir)
CORS(app)
socketio = SocketIO(app, cors_allowed_origins="*", max_http_buffer_size=20 * 1024 * 1024, async_mode='threading')


# --- Tesseract Configuration ---
try:
    # Set path explicitly if needed (examples commented out)
    # pytesseract.pytesseract.tesseract_cmd = r'C:\Program Files\Tesseract-OCR\tesseract.exe' # Windows
    # pytesseract.pytesseract.tesseract_cmd = r'/opt/homebrew/bin/tesseract' # macOS Apple Silicon
    tesseract_version = pytesseract.get_tesseract_version()
    logger.info(f"Tesseract OCR Engine found automatically. Version: {tesseract_version}")
except pytesseract.TesseractNotFoundError:
    logger.error("TesseractNotFoundError: Tesseract is not installed or not in your PATH.")
except Exception as e:
     logger.error(f"Error configuring Tesseract path or getting version: {e}")


# --- Database Configuration & Setup ---
DB_URI = os.environ.get('DATABASE_URL', 'mysql+pymysql://root:@127.0.0.1:3306/visualaiddb')
app.config['SQLALCHEMY_DATABASE_URI'] = DB_URI
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
app.config['SQLALCHEMY_ECHO'] = False
db = SQLAlchemy(app)

def test_db_connection():
    """Tests the database connection."""
    try:
        with app.app_context():
            with db.engine.connect() as connection:
                connection.execute(db.text("SELECT 1"))
                logger.info("Database connection successful!")
                return True
    except Exception as e:
        logger.error(f"Database connection failed: {e}", exc_info=False)
        return False

class User(db.Model):
    """Represents a user in the database."""
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


# --- ML Model Loading ---
logger.info("Loading ML models...")
try:
    # --- Load YOLO-World Model ---
    logger.info("Loading YOLO-World model...")
    # Using Medium Model for potentially better accuracy
    # Options: 'yolo_world_v2-s.pt', 'yolo_world_v2-m.pt', 'yolo_world_v2-l.pt'
    # yolo_model_path = 'yolov8x-worldv2.pt', you can download your preferred model from this link
    # https://huggingface.co/Bingsu/yolo-world-mirror/tree/main
    yolo_model_path = 'yolov8x-worldv2.pt'
    yolo_model = YOLO(yolo_model_path)
    logger.info(f"YOLO-World model loaded from {yolo_model_path}.")

    # --- !!! IMPORTANT: Define the target classes for YOLO-World !!! ---
    # This list MUST contain all object types you want the model to potentially identify.
    TARGET_CLASSES = [
        # --- Standard COCO Classes ---
        'person', 'bicycle', 'car', 'motorcycle', 'airplane', 'bus', 'train', 'truck', 'boat',
        'traffic light', 'fire hydrant', 'stop sign', 'parking meter', 'bench', 'bird', 'cat', 'dog',
        'horse', 'sheep', 'cow', 'elephant', 'bear', 'zebra', 'giraffe', 'backpack', 'umbrella',
        'handbag', 'tie', 'suitcase', 'frisbee', 'skis', 'snowboard', 'sports ball', 'kite',
        'baseball bat', 'baseball glove', 'skateboard', 'surfboard', 'tennis racket', 'bottle',
        'wine glass', 'cup', 'fork', 'knife', 'spoon', 'bowl', 'banana', 'apple', 'sandwich',
        'orange', 'broccoli', 'carrot', 'hot dog', 'pizza', 'donut', 'cake', 'chair', 'couch',
        'potted plant', 'bed', 'dining table', 'toilet', 'tv', 'laptop', 'mouse', 'remote',
        'keyboard', 'cell phone', 'microwave', 'oven', 'toaster', 'sink', 'refrigerator', 'book',
        'clock', 'vase', 'scissors', 'teddy bear', 'hair drier', 'toothbrush',
        # --- Add MORE classes relevant to your application ---
        'traffic cone', 'pen', 'stapler', 'monitor', 'speaker', 'desk lamp', 'trash can', 'bin',
        'stairs', 'door', 'window', 'picture frame', 'whiteboard', 'projector', 'ceiling fan',
        'pillow', 'blanket', 'towel', 'soap', 'shampoo', 'power outlet', 'light switch',
        'screwdriver', 'hammer', 'wrench', 'pliers', 'wheelchair', 'crutches', 'walker', 'cane',
        'plate', 'mug', 'wallet', 'keys', 'glasses', 'sunglasses', 'watch', 'jacket', 'shirt',
        'pants', 'shorts', 'shoes', 'hat', 'gloves', 'scarf', 'computer monitor', 'desk',
        'cabinet', 'shelf', 'drawer', 'curtain', 'radiator', 'air conditioner', 'fan', 'newspaper',
        'magazine', 'letter', 'envelope', 'box', 'bag', 'basket', 'mop', 'broom', 'bucket',
        'fire extinguisher', 'first aid kit', 'exit sign', 'ramp', 'elevator', 'escalator',
        # ... continue adding potentially hundreds of relevant classes ...
        'lion', 'tiger', 'leopard', 'elephant', 'giraffe', 'zebra', 'horse', 'donkey', 'mule', 'goat',
        'sheep', 'cow', 'pig', 'duck', 'turkey', 'chicken', 'dog', 'cat', 'rabbit', 'fish', 'bird',
        'turtle', 'frog', 'toad', 'snake', 'lizard', 'spider', 'insect', 'crab', 'lobster', 'octopus',
        'starfish', 'shrimp', 'squid', 'clam', 'oyster', 'mussel', 'scallop', 'whale', 'shark', 'ray',
        'fishbowl', 'aquarium', 'pond', 'lake', 'river', 'ocean', 'beach', 'ship', 'boat', 'submarine',
        'car', 'truck', 'bus', 'train', 'airplane', 'helicopter', 'bicycle', 'motorcycle', 'scooter',
        'wheelchair', 'stroller', 'skateboard', 'rollerblades', 'kayak', 'canoe', 'paddleboard',
        'bookshelf', 'book', 'magazine', 'newspaper', 'document', 'paper', 'folder', 'file', 'briefcase',
        'laptop', 'computer', 'tablet', 'smartphone', 'phone', 'headphones', 'speaker', 'microphone',
        'keyboard', 'mouse', 'monitor', 'printer', 'scanner', 'fax', 'copier', 'camera', 'video camera',
        'television', 'projector', 'screen', 'DVD', 'CD', 'video game', 'controller', 'guitar', 'piano',
        
    ]
    logger.info(f"Setting {len(TARGET_CLASSES)} target classes for YOLO-World.")
    yolo_model.set_classes(TARGET_CLASSES)
    logger.info("YOLO-World classes set.")

    # --- Load Places365 Model (Scene Classification) ---
    def load_places365_model():
        logger.info("Loading Places365 model...")
        model = models.resnet50(weights=None)
        model.fc = torch.nn.Linear(model.fc.in_features, 365)
        weights_filename = 'resnet50_places365.pth.tar'
        weights_url = 'http://places2.csail.mit.edu/models_places365/resnet50_places365.pth.tar'
        if not os.path.exists(weights_filename):
            logger.info(f"Downloading Places365 weights to {weights_filename}...")
            try:
                response = requests.get(weights_url, timeout=120)
                response.raise_for_status()
                with open(weights_filename, 'wb') as f: f.write(response.content)
                logger.info("Places365 weights downloaded.")
            except requests.exceptions.RequestException as req_e: logger.error(f"Failed to download Places365 weights: {req_e}"); raise
        else: logger.debug(f"Found existing Places365 weights at {weights_filename}.")
        try:
            checkpoint = torch.load(weights_filename, map_location=torch.device('cpu'))
            state_dict = checkpoint.get('state_dict', checkpoint)
            state_dict = {k.replace('module.', ''): v for k, v in state_dict.items()}
            model.load_state_dict(state_dict)
            logger.info("Places365 model weights loaded.")
            model.eval()
            return model
        except Exception as load_e: logger.error(f"Error loading Places365 weights: {load_e}", exc_info=True); raise
    places_model = load_places365_model()

    # --- Load Places365 Labels ---
    logger.info("Loading Places365 labels...")
    places_labels = []
    places_labels_filename = 'categories_places365.txt'
    places_labels_url = 'https://raw.githubusercontent.com/csailvision/places365/master/categories_places365.txt'
    try:
        if not os.path.exists(places_labels_filename):
             logger.info(f"Downloading Places365 labels to {places_labels_filename}...")
             response = requests.get(places_labels_url, timeout=30)
             response.raise_for_status()
             with open(places_labels_filename, 'w', encoding='utf-8') as f: f.write(response.text)
             logger.info("Downloaded Places365 labels.")
        else: logger.debug(f"Using cached Places365 labels from {places_labels_filename}.")
        with open(places_labels_filename, 'r', encoding='utf-8') as f:
            for line in f:
                if line.strip(): parts = line.strip().split(' '); label = parts[0].split('/')[-1]; places_labels.append(label)
        if len(places_labels) != 365: logger.warning(f"Loaded {len(places_labels)} Places365 labels (expected 365).")
        logger.info(f"Loaded {len(places_labels)} Places365 labels.")
    except Exception as e:
        logger.error(f"Failed to load Places365 labels: {e}", exc_info=True)
        places_labels = [f"Label {i}" for i in range(365)]; logger.warning("Using fallback Places365 labels.")

    # --- Tesseract Supported Languages ---
    SUPPORTED_OCR_LANGS = {
        'eng', 'ara', 'fas', 'urd', 'uig', 'hin', 'mar', 'nep', 'rus',
        'chi_sim', 'chi_tra', 'jpn', 'kor', 'tel', 'kan', 'ben',
    }
    DEFAULT_OCR_LANG = 'eng'
    logger.info(f"Tesseract OCR configured. Supported languages (if installed): {SUPPORTED_OCR_LANGS}")
    logger.info(f"Default Tesseract OCR language: {DEFAULT_OCR_LANG}")

    # --- Image Transforms for Scene Classification ---
    scene_transform = transforms.Compose([
        transforms.Resize((256, 256)),
        transforms.CenterCrop(224),
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
    ])

    logger.info("All ML models and configurations loaded successfully.")

except SystemExit as se: logger.critical(str(se)); sys.exit(1)
except Exception as e: logger.critical(f"FATAL ERROR DURING MODEL LOADING: {e}", exc_info=True); sys.exit(f"Failed model load: {e}")


# --- Detection Functions ---

def detect_objects(image_np):
    """
    Detects objects using YOLO-World and returns up to MAX_OBJECTS_TO_RETURN
    object names, sorted by confidence.

    Args:
        image_np (numpy.ndarray): The input image in BGR format (from OpenCV).

    Returns:
        str: A comma-separated string of the most confident detected object names
             (up to the limit), "No objects detected", or an error message.
    """
    # --- !!! CONTROL PARAMETER: Max number of objects to return !!! ---
    MAX_OBJECTS_TO_RETURN = 3 # Adjust this number as needed (e.g., 1, 3, 5)
    # --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---

    try:
        img_rgb = cv2.cvtColor(image_np, cv2.COLOR_BGR2RGB)
        img_pil = Image.fromarray(img_rgb)

        # Perform inference - adjust confidence threshold as needed
        results = yolo_model.predict(img_pil, conf=0.5, verbose=False)

        detections_with_confidence = [] # List to store (confidence, name) tuples

        # Process results if any detections were made
        if results and results[0].boxes:
            boxes = results[0].boxes
            class_id_to_name = results[0].names # Get class name mapping

            for box in boxes:
                confidence = float(box.conf[0]) # Get confidence score
                class_id = int(box.cls[0])      # Get class index

                if class_id in class_id_to_name:
                    class_name = class_id_to_name[class_id]
                    detections_with_confidence.append((confidence, class_name))
                else:
                    logger.warning(f"Detected class ID {class_id} (conf: {confidence:.2f}) not in names map.")

        # --- Sort, Limit, and Format ---
        if not detections_with_confidence:
            logger.debug("Object detection: No objects found above threshold.")
            return "No objects detected"
        else:
            # Sort by confidence in descending order (highest first)
            detections_with_confidence.sort(key=lambda x: x[0], reverse=True)

            # Limit the number of results
            top_detections = detections_with_confidence[:MAX_OBJECTS_TO_RETURN]

            # Extract just the names
            top_object_names = [name for conf, name in top_detections]

            result_str = ", ".join(top_object_names)
            # Log the top results with confidence for debugging
            log_details = ", ".join([f"{name}({conf:.2f})" for conf, name in top_detections])
            logger.debug(f"Object detection top {len(top_object_names)} results: {log_details}")
            return result_str
        # --- --- --- --- --- --- --- ---

    except Exception as e:
        logger.error(f"Error during YOLO-World object detection: {e}", exc_info=True)
        return "Error in object detection"

def detect_scene(image_np):
    """ Classifies the scene using Places365 model. """
    try:
        img_rgb = cv2.cvtColor(image_np, cv2.COLOR_BGR2RGB)
        img_pil = Image.fromarray(img_rgb)
        img_tensor = scene_transform(img_pil).unsqueeze(0)
        with torch.no_grad():
            outputs = places_model(img_tensor)
            probabilities = torch.softmax(outputs, dim=1)[0]
            top_prob, top_catid = torch.max(probabilities, 0)
            if top_catid.item() < len(places_labels):
                predicted_label = places_labels[top_catid.item()]
                confidence = top_prob.item()
                result_str = f"{predicted_label}"
                logger.debug(f"Scene detection complete: {predicted_label} (Conf: {confidence:.3f})")
                return result_str
            else: logger.warning(f"Places365 ID {top_catid.item()} out of bounds."); return "Unknown Scene"
    except Exception as e: logger.error(f"Error during scene detection: {e}", exc_info=True); return "Error in scene detection"

def detect_text(image_np, language_code=DEFAULT_OCR_LANG):
    """ Performs OCR using Tesseract. """
    logger.debug(f"Starting Tesseract OCR for lang: '{language_code}'...")
    validated_lang = language_code if language_code in SUPPORTED_OCR_LANGS else DEFAULT_OCR_LANG
    if validated_lang != language_code: logger.warning(f"Lang '{language_code}' invalid/unsupported, using '{DEFAULT_OCR_LANG}'.")
    try:
        img_rgb = cv2.cvtColor(image_np, cv2.COLOR_BGR2RGB)
        img_pil = Image.fromarray(img_rgb)
        detected_text = pytesseract.image_to_string(img_pil, lang=validated_lang)
        result_str = detected_text.strip()
        if not result_str: logger.debug(f"Tesseract ({validated_lang}): No text found."); return "No text detected"
        else:
            log_text = result_str.replace('\n', ' ').replace('\r', '')[:100]; logger.debug(f"Tesseract ({validated_lang}) OK: Found '{log_text}...'"); return result_str
    except pytesseract.TesseractNotFoundError: logger.error("Tesseract executable not found."); return "Error: OCR Engine Not Found"
    except pytesseract.TesseractError as tess_e:
        logger.error(f"TesseractError ({validated_lang}): {tess_e}", exc_info=False)
        error_str = str(tess_e).lower()
        if "failed loading language" in error_str or "could not initialize tesseract" in error_str:
             logger.warning(f"Missing lang pack for '{validated_lang}'? Install tesseract-ocr-{validated_lang}.")
             if validated_lang != DEFAULT_OCR_LANG:
                 logger.warning(f"Attempting fallback OCR with '{DEFAULT_OCR_LANG}'...")
                 try:
                    img_rgb_fallback = cv2.cvtColor(image_np, cv2.COLOR_BGR2RGB); img_pil_fallback = Image.fromarray(img_rgb_fallback)
                    fallback_text = pytesseract.image_to_string(img_pil_fallback, lang=DEFAULT_OCR_LANG)
                    fallback_result = fallback_text.strip()
                    if not fallback_result: return "No text detected (fallback)"
                    else: log_fallback_text = fallback_result.replace('\n', ' ').replace('\r', '')[:100]; logger.debug(f"Tesseract fallback ({DEFAULT_OCR_LANG}) OK: '{log_fallback_text}...'"); return fallback_result
                 except Exception as fallback_e: logger.error(f"Fallback OCR error: {fallback_e}"); return "Error during OCR fallback"
             else: return f"Error: OCR failed for '{validated_lang}'"
        else: return f"Error during text detection ({validated_lang})"
    except Exception as e: logger.error(f"Unexpected OCR error ({validated_lang}): {e}", exc_info=True); return f"Error during text detection ({validated_lang})"


# --- WebSocket Handlers ---
@socketio.on('connect')
def handle_connect():
    """ Handles new client connections. """
    logger.info(f'Client connected: {request.sid}')
    emit('response', {'result': 'Connected to VisionAid backend', 'event': 'connect'})

@socketio.on('disconnect')
def handle_disconnect():
    """ Handles client disconnections. """
    logger.info(f'Client disconnected: {request.sid}')

@socketio.on('message')
def handle_message(data):
    """ Handles incoming messages for detection. """
    client_sid = request.sid; start_time = time.time(); detection_type = "unknown"
    try:
        if not isinstance(data, dict): logger.warning(f"Invalid data format from {client_sid}."); emit('response', {'result': 'Error: Invalid data format'}); return
        image_data = data.get('image'); detection_type = data.get('type'); requested_language = DEFAULT_OCR_LANG
        if detection_type == 'text_detection':
            requested_language_from_payload = data.get('language', DEFAULT_OCR_LANG).lower()
            if requested_language_from_payload not in SUPPORTED_OCR_LANGS: logger.warning(f"Client {client_sid} invalid lang '{requested_language_from_payload}', using '{DEFAULT_OCR_LANG}'."); requested_language = DEFAULT_OCR_LANG
            else: requested_language = requested_language_from_payload
        if not image_data or not detection_type: logger.warning(f"Missing 'image' or 'type' from {client_sid}."); emit('response', {'result': "Error: Missing 'image' or 'type'"}); return
        logger.info(f"Processing '{detection_type}' from {client_sid}" + (f", Lang: '{requested_language}'" if detection_type == 'text_detection' else ""))
        try: # Image Decoding
            if ',' in image_data: _, encoded = image_data.split(',', 1)
            else: encoded = image_data
            image_bytes = base64.b64decode(encoded)
            image_np = cv2.imdecode(np.frombuffer(image_bytes, np.uint8), cv2.IMREAD_COLOR)
            if image_np is None: raise ValueError("cv2.imdecode failed")
        except (base64.binascii.Error, ValueError) as decode_err: logger.error(f"Image decode error for {client_sid}: {decode_err}"); emit('response', {'result': 'Error: Invalid image data'}); return
        except Exception as decode_e: logger.error(f"Unexpected image decode error for {client_sid}: {decode_e}", exc_info=True); emit('response', {'result': 'Error: Could not process image'}); return
        # Perform Detection
        result = "Error: Unknown processing error"
        if detection_type == 'object_detection': result = detect_objects(image_np) # Calls updated function
        elif detection_type == 'scene_detection': result = detect_scene(image_np)
        elif detection_type == 'text_detection': result = detect_text(image_np, language_code=requested_language)
        else: logger.warning(f"Unsupported type '{detection_type}' from {client_sid}"); result = f"Error: Unsupported type '{detection_type}'"
        processing_time = time.time() - start_time
        log_result = str(result).replace('\n', ' ').replace('\r', '')[:150]
        logger.info(f"Completed '{detection_type}' for {client_sid} in {processing_time:.3f}s. Result: '{log_result}...'" if len(str(result)) > 150 else f"Completed '{detection_type}' for {client_sid} in {processing_time:.3f}s. Result: '{log_result}'")
        emit('response', {'result': result})
    except Exception as e:
        processing_time = time.time() - start_time; logger.error(f"Unhandled error processing '{detection_type}' for {client_sid} after {processing_time:.3f}s: {e}", exc_info=True)
        try: emit('response', {'result': f'Server Error: Unexpected error.'})
        except Exception as emit_e: logger.error(f"Failed to emit error response to {client_sid}: {emit_e}")


# --- Old Test page handlers (Reference Only) ---
# Update these if you actively use test.html and need specific formats
@socketio.on('detect-objects')
def handle_detect_objects_test(data): pass
@socketio.on('detect-scene')
def handle_detect_scene_test(data): pass
@socketio.on('ocr')
def handle_ocr_test(data): pass

# --- Default SocketIO Error Handler ---
@socketio.on_error_default
def default_error_handler(e):
    logger.error(f'Unhandled WebSocket Error: {e}', exc_info=True)
    try:
        if request and request.sid: emit('response', {'result': f'Server Error: Internal WebSocket error.'}, room=request.sid)
    except Exception as emit_err: logger.error(f"Failed emit default error response: {emit_err}")

# --- HTTP Routes (Keep as is) ---
@app.route('/')
def home():
    test_html_path = os.path.join(template_dir, 'test.html')
    if os.path.exists(test_html_path): return render_template('test.html')
    else: return "VisionAid Backend is running."
@app.route('/update_customization', methods=['POST'])
def update_customization(): pass # Keep existing implementation
@app.route('/get_user_info', methods=['GET'])
def get_user_info(): pass # Keep existing implementation
@app.route('/add_test_user', methods=['POST'])
def add_test_user(): pass # Keep existing implementation


# --- Main Execution Point ---
if __name__ == '__main__':
    logger.info("Starting Flask-SocketIO server...")
    host_ip = os.environ.get('FLASK_HOST', '0.0.0.0')
    port_num = int(os.environ.get('FLASK_PORT', 5000))
    debug_mode = os.environ.get('FLASK_DEBUG', 'True').lower() == 'true'
    use_reloader = debug_mode
    logger.info(f"Server listening on {host_ip}:{port_num} (Debug: {debug_mode}, Reloader: {use_reloader})")
    try:
        socketio.run(app, debug=debug_mode, host=host_ip, port=port_num, use_reloader=use_reloader, allow_unsafe_werkzeug=True if use_reloader else False)
    except Exception as run_e: logger.critical(f"Failed to start server: {run_e}", exc_info=True); sys.exit(1)
    finally: logger.info("Server shutdown.")