import struct
import unittest
from locres_v3 import Locres, MAGIC

def string(value):
    data = value.encode('utf-16le') + b'\0\0'
    return struct.pack('<i', -len(data)//2) + data

def fixture():
    prefix = bytearray(MAGIC + b'\x03' + b'\0'*8 + struct.pack('<II',3,1))
    prefix += struct.pack('<I',42) + string('namespace') + struct.pack('<I',3)
    for n, key in enumerate(['flare','ordinary_firelight','second_flare']):
        prefix += struct.pack('<I',n) + string(key) + struct.pack('<Ii',100+n,0)
    struct.pack_into('<q',prefix,17,len(prefix))
    return bytes(prefix) + struct.pack('<i',1) + string('火光') + struct.pack('<i',3)

class Tests(unittest.TestCase):
    def test_zero_change_is_byte_exact(self):
        self.assertEqual(Locres(fixture()).patch({}),fixture())
    def test_shared_string_does_not_change_other_entry(self):
        original=Locres(fixture())
        patched=Locres(original.patch({('namespace','flare'):'核爆',('namespace','second_flare'):'核爆'}))
        self.assertEqual(patched.text(patched.by_key['namespace','ordinary_firelight']),'火光')
        self.assertEqual(patched.references,[1,2])
        self.assertEqual(patched.pool,['火光','核爆'])
        for key,entry in original.by_key.items(): self.assertEqual(patched.by_key[key].source_hash,entry.source_hash)
    def test_bad_version_is_rejected(self):
        value=bytearray(fixture());value[16]=4
        with self.assertRaises(ValueError):Locres(value)
    def test_truncated_or_bad_reference_is_rejected(self):
        with self.assertRaises(ValueError):Locres(fixture()[:15])
        value=bytearray(fixture());struct.pack_into('<i',value,len(value)-4,9)
        with self.assertRaises(ValueError):Locres(value)

if __name__=='__main__':unittest.main()
