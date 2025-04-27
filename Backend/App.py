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
    tesseract_version = pytesseract.get_tesseract_version()
    logger.info(f"Tesseract OCR Engine found automatically. Version: {tesseract_version}")
except pytesseract.TesseractNotFoundError: logger.error("TesseractNotFoundError: Tesseract not installed or not in PATH.")
except Exception as e: logger.error(f"Error configuring Tesseract: {e}")


# --- Database Configuration & Setup ---
DB_URI = os.environ.get('DATABASE_URL', 'mysql+pymysql://root:@127.0.0.1:3306/visualaiddb')
app.config['SQLALCHEMY_DATABASE_URI'] = DB_URI
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
app.config['SQLALCHEMY_ECHO'] = False
db = SQLAlchemy(app)

# (Keep DB test function and User model as before)
def test_db_connection():
    try:
        with app.app_context():
            with db.engine.connect() as connection: connection.execute(db.text("SELECT 1")); logger.info("DB connection OK!"); return True
    except Exception as e: logger.error(f"DB connection failed: {e}", exc_info=False); return False
class User(db.Model):
    __tablename__ = 'users'; id = db.Column(db.Integer, primary_key=True); name = db.Column(db.String(255), nullable=False); email = db.Column(db.String(255), nullable=False, unique=True); password = db.Column(db.String(255), nullable=False); customization = db.Column(db.String(255), default='0' * 255)
with app.app_context():
    try: db.create_all();
    except Exception as e: logger.error(f"Error during DB setup: {e}", exc_info=True)

# --- Constants ---
# Object detection confidence threshold
OBJECT_DETECTION_CONFIDENCE = 0.35
# Max objects to return in normal mode
MAX_OBJECTS_TO_RETURN = 3


# --- ML Model Loading ---
logger.info("Loading ML models...")
try:
    # --- Load YOLO-World Model ---
    logger.info("Loading YOLO-World model...")
    # yolo_model_path = 'yolov8x-worldv2.pt', you can download your preferred model from this link
    # https://huggingface.co/Bingsu/yolo-world-mirror/tree/main
    yolo_model_path = 'yolov8x-worldv2.pt'
    yolo_model = YOLO(yolo_model_path)
    logger.info(f"YOLO-World model loaded from {yolo_model_path}.")

    # --- Define TARGET_CLASSES for YOLO-World (Crucial!) ---
    # This list *must* contain potential objects you want the model to recognize,
    # even in focus mode (it helps the model calibrate).
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
        'pillow', 'blanket', 'towel', 'soap', 'shampoo', 'power outlet', 'light switch', 'keys',
        # ... continue adding ...
    ]
    logger.info(f"Setting {len(TARGET_CLASSES)} target classes for YOLO-World.")
    yolo_model.set_classes(TARGET_CLASSES)
    logger.info("YOLO-World classes set.")

    # --- Load Places365 Model ---
    # (Keep the load_places365_model function as before)
    def load_places365_model():
        logger.info("Loading Places365 model..."); model = models.resnet50(weights=None); model.fc = torch.nn.Linear(model.fc.in_features, 365); weights_filename = 'resnet50_places365.pth.tar'; weights_url = 'http://places2.csail.mit.edu/models_places365/resnet50_places365.pth.tar'
        if not os.path.exists(weights_filename): logger.info(f"Downloading Places365 weights..."); response = requests.get(weights_url, timeout=120); response.raise_for_status(); f = open(weights_filename, 'wb'); f.write(response.content); f.close(); logger.info("Places365 weights downloaded.")
        checkpoint = torch.load(weights_filename, map_location=torch.device('cpu')); state_dict = checkpoint.get('state_dict', checkpoint); state_dict = {k.replace('module.', ''): v for k, v in state_dict.items()}; model.load_state_dict(state_dict); logger.info("Places365 model weights loaded."); model.eval(); return model
    places_model = load_places365_model()

    # --- Load Places365 Labels ---
    # (Keep the Places365 label loading logic as before)
    places_labels = []; places_labels_filename = 'categories_places365.txt'; places_labels_url = 'https://raw.githubusercontent.com/csailvision/places365/master/categories_places365.txt'
    try:
        if not os.path.exists(places_labels_filename): logger.info(f"Downloading Places365 labels..."); response = requests.get(places_labels_url, timeout=30); response.raise_for_status(); f = open(places_labels_filename, 'w', encoding='utf-8'); f.write(response.text); f.close(); logger.info("Places365 labels downloaded.")
        with open(places_labels_filename, 'r', encoding='utf-8') as f:
            for line in f:
                if line.strip(): parts = line.strip().split(' '); label = parts[0].split('/')[-1]; places_labels.append(label)
        logger.info(f"Loaded {len(places_labels)} Places365 labels.")
    except Exception as e: logger.error(f"Failed to load Places365 labels: {e}", exc_info=True); places_labels = [f"Label {i}" for i in range(365)]; logger.warning("Using fallback Places365 labels.")

    # --- Tesseract Supported Languages ---
    SUPPORTED_OCR_LANGS = {'eng', 'ara', 'fas', 'urd', 'uig', 'hin', 'mar', 'nep', 'rus','chi_sim', 'chi_tra', 'jpn', 'kor', 'tel', 'kan', 'ben'}
    DEFAULT_OCR_LANG = 'eng'
    logger.info(f"Tesseract OCR: Supported={SUPPORTED_OCR_LANGS}, Default={DEFAULT_OCR_LANG}")

    # --- Image Transforms for Scene Classification ---
    scene_transform = transforms.Compose([transforms.Resize((256, 256)), transforms.CenterCrop(224), transforms.ToTensor(), transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])])

    logger.info("All ML models loaded.")

except Exception as e: logger.critical(f"FATAL ERROR DURING MODEL LOADING: {e}", exc_info=True); sys.exit(f"Model load failed: {e}")


# --- Detection Functions ---

def detect_objects(image_np, focus_object=None):
    """
    Detects objects using YOLO-World.
    If focus_object is provided, returns details of the most confident match for that object.
    Otherwise, returns up to MAX_OBJECTS_TO_RETURN most confident objects.

    Args:
        image_np (numpy.ndarray): Input image in BGR format.
        focus_object (str, optional): The specific object class to focus on. Defaults to None.

    Returns:
        dict: A dictionary containing detection results. Structure depends on focus_object:
              - Normal mode: {'status': 'ok', 'detections': [{'name': str, 'confidence': float}, ...]}
              - Focus mode (found): {'status': 'found', 'detection': {'name': str, 'confidence': float, 'center_x': float, 'center_y': float, 'width': float, 'height': float}}
              - Focus mode (not found): {'status': 'not_found'}
              - No objects detected: {'status': 'none'}
              - Error: {'status': 'error', 'message': str}
    """
    try:
        img_rgb = cv2.cvtColor(image_np, cv2.COLOR_BGR2RGB)
        img_pil = Image.fromarray(img_rgb)

        # --- Perform inference ---
        # Note: We predict for all TARGET_CLASSES even in focus mode.
        # Filtering happens *after* prediction. This is generally more robust
        # for open-vocabulary models than constantly changing the target class list.
        results = yolo_model.predict(img_pil, conf=OBJECT_DETECTION_CONFIDENCE, verbose=False)

        all_detections = [] # Store (confidence, name, box_details) tuples

        # --- Process raw detections ---
        if results and results[0].boxes:
            boxes = results[0].boxes
            class_id_to_name = results[0].names

            for box in boxes:
                confidence = float(box.conf[0])
                class_id = int(box.cls[0])

                if class_id in class_id_to_name:
                    class_name = class_id_to_name[class_id]
                    # Get normalized bounding box coordinates [x1, y1, x2, y2]
                    norm_box = box.xyxyn[0].tolist() # Use .tolist() for JSON compatibility
                    # Calculate center, width, height (normalized)
                    x1, y1, x2, y2 = norm_box
                    center_x = (x1 + x2) / 2.0
                    center_y = (y1 + y2) / 2.0
                    width = x2 - x1
                    height = y2 - y1
                    box_details = {
                        'name': class_name,
                        'confidence': confidence,
                        'center_x': center_x,
                        'center_y': center_y,
                        'width': width,
                        'height': height
                    }
                    all_detections.append((confidence, class_name, box_details))
                else:
                    logger.warning(f"Unknown class ID {class_id} detected.")
        # --- --- --- --- --- --- --- ---

        # --- Handle Focus Mode ---
        if focus_object:
            focus_object_lower = focus_object.lower()
            found_focus_detections = []
            for conf, name, details in all_detections:
                if name.lower() == focus_object_lower:
                    found_focus_detections.append((conf, details)) # Store confidence and full details

            if not found_focus_detections:
                logger.debug(f"Focus mode: '{focus_object}' not found.")
                return {'status': 'not_found'}
            else:
                # Sort the *found* focus objects by confidence and take the best one
                found_focus_detections.sort(key=lambda x: x[0], reverse=True)
                best_focus_conf, best_focus_details = found_focus_detections[0]
                logger.debug(f"Focus mode: Found '{focus_object}' (Conf: {best_focus_conf:.3f}) at center ({best_focus_details['center_x']:.2f}, {best_focus_details['center_y']:.2f})")
                return {'status': 'found', 'detection': best_focus_details}
        # --- --- --- --- --- --- ---

        # --- Handle Normal Mode (No focus_object) ---
        else:
            if not all_detections:
                logger.debug("Normal mode: No objects detected.")
                return {'status': 'none'}
            else:
                # Sort all detections by confidence
                all_detections.sort(key=lambda x: x[0], reverse=True)
                # Limit the number of results
                top_detections_data = [details for conf, name, details in all_detections[:MAX_OBJECTS_TO_RETURN]]

                # Log details (optional)
                log_summary = ", ".join([f"{d['name']}({d['confidence']:.2f})" for d in top_detections_data])
                logger.debug(f"Normal mode: Top {len(top_detections_data)} results: {log_summary}")

                return {'status': 'ok', 'detections': top_detections_data}
        # --- --- --- --- --- --- --- ---

    except Exception as e:
        logger.error(f"Error during object detection (Focus: {focus_object}): {e}", exc_info=True)
        return {'status': 'error', 'message': "Error in object detection"}

# (Keep detect_scene and detect_text functions as they were in the previous version)
def detect_scene(image_np):
    """ Classifies the scene using Places365 model. """
    try:
        img_rgb = cv2.cvtColor(image_np, cv2.COLOR_BGR2RGB); img_pil = Image.fromarray(img_rgb); img_tensor = scene_transform(img_pil).unsqueeze(0)
        with torch.no_grad(): outputs = places_model(img_tensor); probabilities = torch.softmax(outputs, dim=1)[0]; top_prob, top_catid = torch.max(probabilities, 0)
        if top_catid.item() < len(places_labels): predicted_label = places_labels[top_catid.item()]; confidence = top_prob.item(); result_str = f"{predicted_label}"; logger.debug(f"Scene: {predicted_label} (Conf: {confidence:.3f})"); return result_str
        else: logger.warning(f"Places365 ID {top_catid.item()} out of bounds."); return "Unknown Scene"
    except Exception as e: logger.error(f"Scene detection error: {e}", exc_info=True); return "Error in scene detection"
def detect_text(image_np, language_code=DEFAULT_OCR_LANG):
    """ Performs OCR using Tesseract. """
    logger.debug(f"Starting Tesseract OCR for lang: '{language_code}'..."); validated_lang = language_code if language_code in SUPPORTED_OCR_LANGS else DEFAULT_OCR_LANG
    if validated_lang != language_code: logger.warning(f"Lang '{language_code}' invalid/unsupported, using '{DEFAULT_OCR_LANG}'.")
    try:
        img_rgb = cv2.cvtColor(image_np, cv2.COLOR_BGR2RGB); img_pil = Image.fromarray(img_rgb); detected_text = pytesseract.image_to_string(img_pil, lang=validated_lang); result_str = detected_text.strip()
        if not result_str: logger.debug(f"Tesseract ({validated_lang}): No text."); return "No text detected"
        else: log_text = result_str.replace('\n', ' ').replace('\r', '')[:100]; logger.debug(f"Tesseract ({validated_lang}) OK: Found '{log_text}...'"); return result_str
    except pytesseract.TesseractNotFoundError: logger.error("Tesseract not found."); return "Error: OCR Engine Not Found"
    except pytesseract.TesseractError as tess_e:
        logger.error(f"TesseractError ({validated_lang}): {tess_e}", exc_info=False); error_str = str(tess_e).lower()
        if "failed loading language" in error_str or "could not initialize tesseract" in error_str:
             logger.warning(f"Missing lang pack for '{validated_lang}'?");
             if validated_lang != DEFAULT_OCR_LANG:
                 logger.warning(f"Attempting fallback OCR with '{DEFAULT_OCR_LANG}'...");
                 try: img_rgb_fallback = cv2.cvtColor(image_np, cv2.COLOR_BGR2RGB); img_pil_fallback = Image.fromarray(img_rgb_fallback); fallback_text = pytesseract.image_to_string(img_pil_fallback, lang=DEFAULT_OCR_LANG); fallback_result = fallback_text.strip()
                 except Exception as fallback_e: logger.error(f"Fallback OCR error: {fallback_e}"); return "Error during OCR fallback"
                 if not fallback_result: return "No text detected (fallback)"
                 else: log_fallback_text = fallback_result.replace('\n', ' ').replace('\r', '')[:100]; logger.debug(f"Tesseract fallback OK: '{log_fallback_text}...'"); return fallback_result
             else: return f"Error: OCR failed for '{validated_lang}'"
        else: return f"Error during text detection ({validated_lang})"
    except Exception as e: logger.error(f"Unexpected OCR error ({validated_lang}): {e}", exc_info=True); return f"Error during text detection ({validated_lang})"


# --- WebSocket Handlers ---
@socketio.on('connect')
def handle_connect(): logger.info(f'Client connected: {request.sid}'); emit('response', {'result': 'Connected', 'event': 'connect'})
@socketio.on('disconnect')
def handle_disconnect(): logger.info(f'Client disconnected: {request.sid}')

@socketio.on('message')
def handle_message(data):
    """Handles incoming messages for detection."""
    client_sid = request.sid; start_time = time.time(); detection_type = "unknown"; result = None
    try:
        if not isinstance(data, dict): logger.warning(f"Invalid data format from {client_sid}."); emit('response', {'result': {'status': 'error', 'message': 'Invalid data format'}}); return

        image_data = data.get('image')
        detection_type = data.get('type') # e.g., 'object_detection', 'scene_detection', 'text_detection', 'focus_detection'
        requested_language = DEFAULT_OCR_LANG
        focus_object_name = None # For focus mode

        # --- Get parameters based on type ---
        if detection_type == 'text_detection':
            lang_payload = data.get('language', DEFAULT_OCR_LANG).lower()
            requested_language = lang_payload if lang_payload in SUPPORTED_OCR_LANGS else DEFAULT_OCR_LANG
            if requested_language != lang_payload: logger.warning(f"Client {client_sid} invalid lang '{lang_payload}', using '{DEFAULT_OCR_LANG}'.")
        elif detection_type == 'focus_detection':
            focus_object_name = data.get('focus_object')
            if not focus_object_name:
                logger.warning(f"Focus detection request from {client_sid} missing 'focus_object'.")
                emit('response', {'result': {'status': 'error', 'message': "Missing 'focus_object' for focus detection"}}); return
        # --- --- --- --- --- --- --- --- --- ---

        if not image_data or not detection_type: logger.warning(f"Missing 'image' or 'type' from {client_sid}."); emit('response', {'result': {'status': 'error', 'message': "Missing 'image' or 'type'"}}); return

        log_extra = ""
        if detection_type == 'text_detection': log_extra = f", Lang: '{requested_language}'"
        elif detection_type == 'focus_detection': log_extra = f", Focus: '{focus_object_name}'"
        logger.info(f"Processing '{detection_type}' from {client_sid}{log_extra}")

        # --- Image Decoding ---
        try:
            if ',' in image_data: _, encoded = image_data.split(',', 1)
            else: encoded = image_data
            image_bytes = base64.b64decode(encoded)
            image_np = cv2.imdecode(np.frombuffer(image_bytes, np.uint8), cv2.IMREAD_COLOR)
            if image_np is None: raise ValueError("cv2.imdecode failed")
        except Exception as decode_err: logger.error(f"Image decode error for {client_sid}: {decode_err}", exc_info=True); emit('response', {'result': {'status': 'error', 'message': 'Invalid image data'}}); return
        # --- --- --- --- --- ---

        # --- Perform Detection ---
        if detection_type == 'object_detection':
            result = detect_objects(image_np) # Normal mode
        elif detection_type == 'focus_detection':
            result = detect_objects(image_np, focus_object=focus_object_name) # Focus mode
        elif detection_type == 'scene_detection':
            # Scene detection doesn't usually return structured status, wrap it for consistency
            scene_label = detect_scene(image_np)
            if "Error" in scene_label: result = {'status': 'error', 'message': scene_label}
            elif "Unknown" in scene_label: result = {'status': 'none'} # Or 'ok' with label? Depends on FE.
            else: result = {'status': 'ok', 'scene': scene_label}
        elif detection_type == 'text_detection':
            # Wrap text detection result
            text_result = detect_text(image_np, language_code=requested_language)
            if "Error" in text_result: result = {'status': 'error', 'message': text_result}
            elif "No text detected" in text_result: result = {'status': 'none'}
            else: result = {'status': 'ok', 'text': text_result}
        else:
            logger.warning(f"Unsupported type '{detection_type}' from {client_sid}")
            result = {'status': 'error', 'message': f"Unsupported detection type '{detection_type}'"}
        # --- --- --- --- --- ---

        processing_time = time.time() - start_time
        # Log status and maybe primary result for quick check
        status_log = result.get('status', 'unknown') if isinstance(result, dict) else 'raw'
        log_detail = ""
        if isinstance(result, dict):
            if result.get('status') == 'ok' and result.get('detections'): log_detail = f": {len(result['detections'])} objects"
            elif result.get('status') == 'found': log_detail = f": Found '{result['detection']['name']}'"
            elif result.get('status') == 'ok' and result.get('scene'): log_detail = f": Scene '{result['scene']}'"
            elif result.get('status') == 'ok' and result.get('text'): log_detail = f": Text found" # Avoid logging text itself
        logger.info(f"Completed '{detection_type}' for {client_sid} in {processing_time:.3f}s. Status: {status_log}{log_detail}")

        emit('response', {'result': result}) # Send the structured result back

    except Exception as e:
        processing_time = time.time() - start_time
        logger.error(f"Unhandled error in handle_message ('{detection_type}') for {client_sid} after {processing_time:.3f}s: {e}", exc_info=True)
        try: emit('response', {'result': {'status': 'error', 'message': 'Internal server error during processing.'}})
        except Exception as emit_e: logger.error(f"Failed to emit error response to {client_sid}: {emit_e}")


# --- Old Test page handlers (Reference Only) ---
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
        if request and request.sid: emit('response', {'result': {'status': 'error', 'message': 'Internal WebSocket error.'}}, room=request.sid)
    except Exception as emit_err: logger.error(f"Failed emit default error response: {emit_err}")

# --- HTTP Routes (Keep as is) ---
@app.route('/')
def home(): test_html_path = os.path.join(template_dir, 'test.html'); return render_template('test.html') if os.path.exists(test_html_path) else "VisionAid Backend is running."
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