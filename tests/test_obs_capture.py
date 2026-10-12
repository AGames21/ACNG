import sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import obs_capture
class ObsCaptureTests(unittest.TestCase):
 def test_unowned_obs_is_rejected_before_launch(self):
  import tempfile
  with tempfile.TemporaryDirectory() as tmp:
   with self.assertRaisesRegex(RuntimeError,'ACNG-owned'):
    obs_capture.ObsRecorder(tmp,tmp,0,2560,1440,60)
 def test_only_game_process_video_and_audio(self):
  inputs=obs_capture.game_inputs('lab:class:BeamNG.drive.x64.exe')
  self.assertEqual([x[1] for x in inputs],['window_capture','wasapi_process_output_capture'])
  self.assertEqual([x[2]['priority'] for x in inputs],[1,2])
  self.assertFalse(inputs[0][2]['cursor'])
  self.assertEqual(inputs[0][2]['method'],2)
  self.assertTrue(inputs[0][2]['client_area'])
