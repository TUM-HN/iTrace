import matplotlib
matplotlib.use('Agg')
import numpy as np
from flask import Flask, request, send_file, jsonify
from flask_cors import CORS
import cv2
import tempfile
import os
import json
import subprocess
import time
from datetime import datetime
import threading
import socket
from zeroconf import ServiceInfo, Zeroconf
import uuid
import shutil
import sys
import argparse
import glob

# Configuration
OUTPUT_DIR = os.path.expanduser("~/Desktop/Heatmap")

# Global state
app = Flask(__name__)
CORS(app)

def find_video_file(folder_path):
    """Find the first video file in the folder"""
    video_extensions = ['*.mp4', '*.avi', '*.mov', '*.mkv', '*.flv', '*.wmv']
    
    for ext in video_extensions:
        video_files = glob.glob(os.path.join(folder_path, ext))
        if video_files:
            print(f"Found video file: {video_files[0]}")
            return video_files[0]
    
    print(f"No video files found in {folder_path}")
    return None

def reduce_video_quality(input_path, max_width=1280, max_height=720, crf=28):
    try:
        cap = cv2.VideoCapture(input_path)
        w, h = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)), int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        cap.release()
        
        scale = min(min(max_width / w, max_height / h), 1.0)
        new_w, new_h = int(w * scale) & ~1, int(h * scale) & ~1
        
        if scale >= 0.95: 
            return input_path, 1.0, 1.0
        
        reduced_path = input_path.replace('.mp4', '_reduced.mp4')
        
        # Check if input has audio and preserve it
        probe_cmd = ['ffprobe', '-v', 'quiet', '-select_streams', 'a', '-show_entries', 'stream=codec_type', '-of', 'csv=p=0', input_path]
        has_audio = False
        try:
            result = subprocess.run(probe_cmd, capture_output=True, text=True)
            has_audio = 'audio' in result.stdout
        except:
            pass
        
        if has_audio:
            cmd = ['ffmpeg', '-i', input_path, '-vf', f'scale={new_w}:{new_h}',
                   '-c:v', 'libx264', '-c:a', 'aac', '-preset', 'ultrafast', '-crf', str(crf), '-y', reduced_path]
        else:
            cmd = ['ffmpeg', '-i', input_path, '-vf', f'scale={new_w}:{new_h}',
                   '-c:v', 'libx264', '-preset', 'ultrafast', '-crf', str(crf), '-an', '-y', reduced_path]
        
        if subprocess.run(cmd, capture_output=True).returncode == 0:
            return reduced_path, new_w / w, new_h / h
        return input_path, 1.0, 1.0
    except:
        return input_path, 1.0, 1.0

def create_heatmap_overlay(brightness_grid, video_width, video_height, base_sigma=40, base_resolution=1920):
    if np.sum(brightness_grid) == 0: 
        return None
    
    resolution_scale = video_width / base_resolution
    scaled_sigma = max(base_sigma * resolution_scale, 5.0)
    
    blurred = cv2.GaussianBlur(brightness_grid.astype(np.float32), (0, 0), scaled_sigma)
    if np.max(blurred) > 0:
        blurred = (blurred / np.max(blurred) * 255).astype(np.uint8)
    return cv2.applyColorMap(blurred, cv2.COLORMAP_INFERNO)

def generate_filename(tracking_data, suffix=""):
    timestamp = tracking_data.get('timestamp', datetime.now().strftime("%Y%m%d_%H%M%S"))
    user_name = tracking_data.get('user_name', 'unknown_user').replace(' ', '_')
    tracking_type = tracking_data.get('tracking_type', 'unknown')
    
    if tracking_data.get('video_name'):
        video_name = os.path.splitext(tracking_data['video_name'])[0].replace(' ', '_')
        base_name = f"{user_name}_{video_name}_{tracking_type}_{timestamp}"
    else:
        base_name = f"{user_name}_{tracking_type}_{timestamp}"
    
    return f"{base_name}{suffix}"

def save_tracking_data(tracking_data, filename_base):
    try:
        os.makedirs(OUTPUT_DIR, exist_ok=True)
        json_path = os.path.join(OUTPUT_DIR, f"{filename_base}_data.json")
        
        with open(json_path, 'w') as f:
            json.dump(tracking_data, f, indent=2)
        
        return json_path
    except Exception as e:
        print(f"Error saving tracking data: {e}")
        return None

def generate_averaged_heatmap(video_path, all_click_data, output_folder=None):
    """Generate averaged heatmap by reusing existing generate_heatmap function"""
    if output_folder is None:
        output_folder = OUTPUT_DIR
    
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    
    # Create fake tracking_data that mimics the expected format
    tracking_data = {
        'click_data': all_click_data,
        'user_name': 'averaged',
        'tracking_type': 'heatmap',
        'timestamp': timestamp
    }
    
    # Use existing generate_heatmap function
    temp_output = generate_heatmap(video_path, tracking_data)
    
    if temp_output and os.path.exists(temp_output):
        # Move to final location with timestamped name
        final_video_path = os.path.join(output_folder, f"averaged_heatmap_{timestamp}.mp4")
        shutil.move(temp_output, final_video_path)
        
        # Load data from original JSON files
        folder_path = os.path.dirname(video_path)
        participants = []
        
        for json_file in glob.glob(os.path.join(folder_path, "*.json")):
            try:
                with open(json_file, 'r') as f:
                    data = json.load(f)
                
                if 'user_name' in data and 'precision_score' in data and 'click_data' in data:
                    participants.append({
                        "user_name": data['user_name'],
                        "click_count": len(data['click_data']),
                        "precision_score": data['precision_score']
                    })
            except Exception as e:
                print(f"Error processing {json_file}: {e}")
        
        summary_data = {
            "participant_count": len(participants),
            "video_name": os.path.basename(video_path),
            "participants": participants,
            "generation_timestamp": timestamp,
            "processing_type": "averaged_heatmap"
        }
        
        summary_path = os.path.join(output_folder, f"averaged_heatmap_{timestamp}.json")
        with open(summary_path, 'w') as f:
            json.dump(summary_data, f, indent=2)
        
        print(f"Averaged heatmap generated: {final_video_path}")
        return final_video_path
    
    return None

def process_folder(folder_path):
    """Process a folder containing JSON files and video to generate averaged heatmap"""    
    if not os.path.exists(folder_path):
        print(f"Error: Folder {folder_path} does not exist")
        return None
    
    # Load all JSON files
    all_click_data = load_json_files(folder_path)
    
    if not all_click_data:
        print("No valid click data found in JSON files")
        return None
    
    # Find video file
    video_path = find_video_file(folder_path)
    
    if not video_path:
        print("No video file found in folder")
        return None
    
    # Generate averaged heatmap
    output_path = generate_averaged_heatmap(video_path, all_click_data, OUTPUT_DIR)
    
    if output_path:
        print(f"Successfully generated averaged heatmap: {output_path}")
        return output_path
    else:
        print("Failed to generate averaged heatmap")
        return None

def generate_heatmap(video_path, tracking_data):
    try:
        reduced_path, scale_x, scale_y = reduce_video_quality(video_path)
        
        filename_base = generate_filename(tracking_data)
        os.makedirs(OUTPUT_DIR, exist_ok=True)
        output_path = os.path.join(OUTPUT_DIR, f"{filename_base}_heatmap.mp4")
        
        save_tracking_data(tracking_data, filename_base)
        
        cap = cv2.VideoCapture(reduced_path)
        if not cap.isOpened(): 
            return None
        
        fps = cap.get(cv2.CAP_PROP_FPS)
        w, h = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)), int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        
        # Create temporary video without audio for processing
        temp_video_path = output_path.replace('.mp4', '_temp.mp4')
        out = cv2.VideoWriter(temp_video_path, cv2.VideoWriter_fourcc(*'mp4v'), fps, (w, h))
        fade_duration = int(fps * 0.3)
        
        click_data = tracking_data.get('click_data', [])
        brightness_per_frame = np.zeros((frame_count, h, w), dtype=np.float32)
        
        for click in click_data:
            x, y = int(float(click["x"]) * w), int(float(click["y"]) * h)
            x, y = min(max(x, 0), w - 1), min(max(y, 0), h - 1)
            
            start_frame = max(0, int((click["timestamp"] * fps) - fade_duration))
            end_frame = min(start_frame + fade_duration * 2, frame_count)
            
            frame_range = np.arange(start_frame, end_frame)
            fade_in = frame_range < start_frame + fade_duration
            fade_out = frame_range >= end_frame - fade_duration
            
            brightness = np.ones_like(frame_range, dtype=np.float32)
            brightness[fade_in] = (frame_range[fade_in] - start_frame) / fade_duration
            brightness[fade_out] = (end_frame - frame_range[fade_out]) / fade_duration
            
            brightness_per_frame[frame_range, y, x] += brightness
        
        max_brightness = np.max(brightness_per_frame)
        if max_brightness > 1.0:
            brightness_per_frame = np.sqrt(brightness_per_frame / max_brightness)
        
        batch_size = 50 if w * h < 1000000 else 25
        for i in range(0, frame_count, batch_size):
            batch_end = min(i + batch_size, frame_count)
            progress = int((i / frame_count) * 100)
            print(f"Video generation: {progress}%")
            
            for j in range(i, batch_end):
                ret, frame = cap.read()
                if not ret: break
                
                darkened = cv2.addWeighted(frame, 0.5, np.zeros_like(frame), 0.5, 0)
                heatmap = create_heatmap_overlay(brightness_per_frame[j], w, h)
                
                if heatmap is not None:
                    result = cv2.addWeighted(darkened, 1.0, heatmap, 0.8, 0)
                else:
                    result = darkened
                
                out.write(result)
        
        # Get the last frame for final heatmap overlay
        cap.set(cv2.CAP_PROP_POS_FRAMES, frame_count - 1)
        ret, last_frame = cap.read()
        if not ret:
            # If we can't get the last frame, reset to beginning and read through
            cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
            for _ in range(frame_count):
                ret, last_frame = cap.read()
                if not ret:
                    last_frame = np.zeros((h, w, 3), dtype=np.uint8)
                    break
        
        # Add final heatmap frame with extended duration
        final_grid = np.zeros((h, w), dtype=np.float32)
        for click in click_data:
            x, y = int(float(click["x"]) * w), int(float(click["y"]) * h)
            if 0 <= x < w and 0 <= y < h:
                final_grid[y, x] += 1
        
        if np.sum(final_grid) > 0:
            if np.max(final_grid) > 1.0:
                final_grid = np.sqrt(final_grid / np.max(final_grid))
            final_heatmap = create_heatmap_overlay(final_grid, w, h)
            if final_heatmap is not None:
                # Darken the last frame and overlay the heatmap
                darkened_last = cv2.addWeighted(last_frame, 0.5, np.zeros_like(last_frame), 0.5, 0)
                final_frame = cv2.addWeighted(darkened_last, 1.0, final_heatmap, 0.8, 0)
                
                out.write(final_frame)
        
        cap.release()
        out.release()
        
        # Check if original video has audio and merge it
        probe_cmd = ['ffprobe', '-v', 'quiet', '-select_streams', 'a', '-show_entries', 'stream=codec_type', '-of', 'csv=p=0', reduced_path]
        has_audio = False
        try:
            result = subprocess.run(probe_cmd, capture_output=True, text=True)
            has_audio = 'audio' in result.stdout
        except:
            pass
        
        if has_audio:
            # Get duration of temp video to ensure audio sync
            duration_cmd = ['ffprobe', '-v', 'quiet', '-show_entries', 'format=duration', '-of', 'csv=p=0', temp_video_path]
            try:
                duration_result = subprocess.run(duration_cmd, capture_output=True, text=True)
                temp_duration = float(duration_result.stdout.strip())
                
                # Merge video with audio
                merge_cmd = [
                    'ffmpeg', '-i', temp_video_path, '-i', reduced_path,
                    '-c:v', 'libx264', '-c:a', 'aac', '-map', '0:v:0', '-map', '1:a:0',
                    '-t', str(temp_duration), 
                    '-y', output_path
                ]
                result = subprocess.run(merge_cmd, capture_output=True)
                if result.returncode == 0:
                    os.unlink(temp_video_path)
                    print("Audio merged successfully")
                else:
                    print(f"Failed to merge audio: {result.stderr.decode() if result.stderr else 'Unknown error'}")
                    shutil.move(temp_video_path, output_path)
                    
            except Exception as e:
                print(f"Error during audio merge: {e}")
                shutil.move(temp_video_path, output_path)
        else:
            print("No audio found in original video")
            shutil.move(temp_video_path, output_path)
        
        if reduced_path != video_path:
            try: 
                os.unlink(reduced_path)
            except: 
                pass
        
        print("Heatmap generation completed")
        return output_path
        
    except Exception as e:
        print(f"Error generating heatmap: {e}")
        return None
      
def find_free_port():
    """Find a random free port"""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(('', 0))
        s.listen(1)
        port = s.getsockname()[1]
    return port

def get_local_ip():
    """Get local IP address, trying multiple interfaces"""
    try:
        # Try connecting to a remote address to get local IP
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("8.8.8.8", 80))
            ip = s.getsockname()[0]
            return ip
    except:
        try:
            # Fallback: get hostname IP
            hostname = socket.gethostname()
            ip = socket.gethostbyname(hostname)
            if ip.startswith("127."):
                # If localhost, try to get actual IP
                with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
                    s.connect(("1.1.1.1", 80))
                    ip = s.getsockname()[0]
            return ip
        except:
            return "127.0.0.1"

def register_service(port):
    try:
        zeroconf = Zeroconf()
        local_ip = get_local_ip()
        hostname = socket.gethostname()
        unique_id = str(uuid.uuid4())[:8]
        service_name = f"Vision Pro Server {unique_id}"
        service_type = "_visionpro._tcp.local."
        
        info = ServiceInfo(
            service_type,
            f"{service_name}.{service_type}",
            addresses=[socket.inet_aton(local_ip)],
            port=port,
            properties={
                'description': 'Apple Vision Pro Heatmap Generation Server',
                'hostname': hostname,
                'unique_id': unique_id
            }
        )
        
        zeroconf.register_service(info)
        print(f"Service registered: {service_name} at {local_ip}:{port}")
        return zeroconf, info
        
    except Exception as e:
        print(f"Failed to register service: {e}")
        return None, None
    
current_recording_process = None
current_recording_filepath = None

@app.route('/start_recording', methods=['POST'])
def start_recording():
    global current_recording_process, current_recording_filepath

    if current_recording_process:
        current_recording_process.terminate()
        current_recording_process.wait()
        current_recording_process = None    
    try:
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        current_recording_filepath = os.path.join(tempfile.gettempdir(), f"temp_recording_{timestamp}.mp4")
        audio_filepath = os.path.join(tempfile.gettempdir(), f"temp_audio_{timestamp}.wav")
        video_filepath = os.path.join(tempfile.gettempdir(), f"temp_video_{timestamp}.mp4")
        
        def record():
            global current_recording_process
            
            # Start SoX audio recording
            audio_cmd = ['sox', '-d', audio_filepath]
            audio_process = subprocess.Popen(audio_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            
            # FFmpeg video recording
            cmd = ['ffmpeg', '-f', 'avfoundation', '-i', '1', '-r', '20', 
                  '-vf', 'crop=iw:ih*0.865:0:ih*0.085,scale=1280:720',
                  '-vcodec', 'libx264', '-preset', 'veryfast', '-crf', '25', 
                  '-pix_fmt', 'yuv420p', '-y', video_filepath]
            current_recording_process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            
            # Wait for video recording to finish
            current_recording_process.wait()
            
            # Stop audio recording
            audio_process.terminate()
            audio_process.wait()
            
            # Merge audio and video
            merge_cmd = [
                'ffmpeg', '-i', video_filepath, '-i', audio_filepath,
                '-c:v', 'copy', '-c:a', 'aac', '-shortest', '-y', current_recording_filepath
            ]
            subprocess.run(merge_cmd, capture_output=True)
            
            # Clean up temp files
            try:
                os.unlink(video_filepath)
                os.unlink(audio_filepath)
            except:
                pass
        
        threading.Thread(target=record).start()
        return jsonify({"status": "success", "message": "Recording with SoX audio started"})
        
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500
    
@app.route('/stop_recording', methods=['POST'])
def stop_recording():
    global current_recording_process, current_recording_filepath
    
    try:
        data = request.get_json()
        tracking_data = data.get('tracking_data', {})
                
        if current_recording_process:
            current_recording_process.terminate()
            current_recording_process.wait()
            current_recording_process = None
            time.sleep(2)
            
            if current_recording_filepath and os.path.exists(current_recording_filepath):
                heatmap_path = generate_heatmap(current_recording_filepath, tracking_data)
                os.unlink(current_recording_filepath)
                
                if heatmap_path:
                    return send_file(heatmap_path, mimetype='video/mp4', download_name='heatmap.mp4')
                else:
                    return jsonify({"status": "error", "message": "Failed to generate heatmap"}), 500
            else:
                return jsonify({"status": "error", "message": "Recording file not found"}), 500
        else:
            return jsonify({"status": "error", "message": "No active recording"}), 400
            
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/generate_heatmap', methods=['POST'])
def generate_heatmap_endpoint():
    try:
        video_file = request.files['video']
        tracking_data = json.loads(request.form.get('tracking_data'))
    
        temp_input = tempfile.NamedTemporaryFile(delete=False, suffix=".mp4")
        video_file.save(temp_input.name)
        
        heatmap_path = generate_heatmap(temp_input.name, tracking_data)
        os.unlink(temp_input.name)
        
        if heatmap_path:
            return send_file(heatmap_path, mimetype='video/mp4', download_name='heatmap.mp4')
        else:
            return jsonify({"status": "error", "message": "Failed to generate heatmap"}), 500
            
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

def main():
    parser = argparse.ArgumentParser(description='Vision Pro Heatmap Server')
    parser.add_argument('--folder', '-f', type=str, help='Folder path containing JSON files and video to process')
    parser.add_argument('--server', '-s', action='store_true', help='Start the Flask server (default behavior)')
    parser.add_argument('--port', '-p', type=int, help='Port to run server on (default: random free port)')
    
    args = parser.parse_args()
    
    if args.folder:
        # Process folder mode
        result = process_folder(args.folder)
        if result:
            sys.exit(0)
        else:
            print("Processing failed")
            sys.exit(1)
    else:
        # Server mode
        port = args.port if args.port else find_free_port()
        local_ip = get_local_ip()
        
        zeroconf, service_info = register_service(port)
        
        try:
            print(f"Server starting on {local_ip}:{port}")
            app.run(host='0.0.0.0', port=port, debug=True)
        finally:
            if zeroconf and service_info:
                zeroconf.unregister_service(service_info)
                zeroconf.close()

if __name__ == "__main__":
    main()