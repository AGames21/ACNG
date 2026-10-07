import ctypes as C
import struct
import unittest
from telemetry.ac_shared_memory import PhysicsPrefix,StaticPrefix,GraphicsPrefix,decode_physics,wide,ExistingMapping


class PrefixTests(unittest.TestCase):
    def test_documented_prefix_layout(self):
        self.assertEqual(C.sizeof(PhysicsPrefix),200)
        self.assertEqual(PhysicsPrefix.speedKmh.offset,28)
        self.assertEqual(PhysicsPrefix.wheelLoad.offset,72)
        self.assertEqual(PhysicsPrefix.suspensionTravel.offset,184)
        self.assertEqual(C.sizeof(StaticPrefix),200)
        self.assertEqual(StaticPrefix.carModel.offset,68)
        self.assertEqual(GraphicsPrefix.iCurrentTime.offset,140)

    def test_independently_packed_scalar_and_wheel(self):
        data=bytearray(200)
        struct.pack_into('<ifffiiff',data,0,10,0.8,0.2,20.0,2,3000,0.3,36.0)
        struct.pack_into('<4f',data,72,1000,2000,3000,4000)
        row=decode_physics(data)
        self.assertAlmostEqual(row['speed_m_s'],10)
        self.assertEqual(row['gear'],1)
        self.assertEqual(row['wheels'][0]['name'],'FL')
        self.assertEqual(row['wheels'][3]['load_n'],4000)

    def test_rejects_wrong_values_and_truncation(self):
        with self.assertRaises(ValueError):decode_physics(b'\0'*199)
        data=bytearray(200)
        struct.pack_into('<f',data,28,float('nan'))
        with self.assertRaises(ValueError):decode_physics(data)

    def test_windows_utf16_independent_of_host_wchar(self):
        a=(C.c_uint16*15)()
        text='1.16.4'.encode('utf-16-le')
        C.memmove(C.addressof(a),text,len(text))
        self.assertEqual(wide(a),'1.16.4')

    def test_absent_mapping_is_not_created(self):
        import os,uuid
        if os.name!='nt':self.skipTest('Windows mapping behavior')
        name='Local\\ACNG_absent_'+uuid.uuid4().hex
        with self.assertRaises(FileNotFoundError):ExistingMapping(name,200)
        with self.assertRaises(FileNotFoundError):ExistingMapping(name,200)


if __name__=='__main__':unittest.main()
