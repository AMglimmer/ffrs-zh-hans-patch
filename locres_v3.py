"""Strict reader and minimal string-index patcher for UE locres version 3.

Namespace/key hashes, source hashes and original string encodings are retained.
Only changed entries receive new pooled strings, avoiding shared-string edits.
"""
from collections import Counter
from dataclasses import dataclass
import struct

MAGIC = bytes.fromhex('0e147475674a03fc4a15909dc3377f1b')

@dataclass
class Entry:
    namespace: str
    key: str
    source_hash: int
    string_index: int
    index_offset: int

class Locres:
    def __init__(self, data: bytes):
        self.data = data
        self.position = 0
        if len(data) < 33 or data[:16] != MAGIC or data[16] != 3:
            raise ValueError('Expected optimized CRC32 locres version 3')
        self.position = 17
        self.pool_offset = self.number('<q')
        total = self.number('<I')
        namespace_count = self.number('<I')
        self.entries = []
        for _ in range(namespace_count):
            self.number('<I')  # namespace key hash
            namespace = self.string()
            count = self.number('<I')
            for _ in range(count):
                self.number('<I')  # text key hash
                key = self.string()
                source_hash = self.number('<I')
                offset = self.position
                index = self.number('<i')
                self.entries.append(Entry(namespace, key, source_hash, index, offset))
        if len(self.entries) != total or self.position != self.pool_offset:
            raise ValueError('Entry count or string-pool offset mismatch')
        count = self.number('<i')
        self.pool = []
        self.pool_raw = []
        self.references = []
        for _ in range(count):
            start = self.position
            self.pool.append(self.string())
            self.pool_raw.append(data[start:self.position])
            self.references.append(self.number('<i'))
        if self.position != len(data):
            raise ValueError('Unexpected trailing bytes')
        used = Counter(e.string_index for e in self.entries)
        if any(i < 0 or i >= count for i in used):
            raise ValueError('Invalid localized string index')
        if any(used[i] != refs for i, refs in enumerate(self.references)):
            raise ValueError('Unexpected string reference counts')
        self.by_key = {(e.namespace, e.key): e for e in self.entries}
        if len(self.by_key) != total:
            raise ValueError('Duplicate namespace/key')

    def number(self, format):
        size = struct.calcsize(format)
        if self.position + size > len(self.data): raise ValueError('Truncated resource')
        value = struct.unpack_from(format, self.data, self.position)[0]
        self.position += size
        return value

    def string(self):
        count = self.number('<i')
        size = abs(count) * (2 if count < 0 else 1)
        if self.position + size > len(self.data): raise ValueError('Truncated string')
        raw = self.data[self.position:self.position + size]
        self.position += size
        if count == 0: return ''
        null = b'\0\0' if count < 0 else b'\0'
        if not raw.endswith(null): raise ValueError('Missing string terminator')
        return raw[:-len(null)].decode('utf-16le' if count < 0 else 'utf-8')

    def text(self, entry):
        return self.pool[entry.string_index]

    def patch(self, replacements):
        prefix = bytearray(self.data[:self.pool_offset])
        references = self.references.copy()
        additions = {}
        for key, new in replacements.items():
            entry = self.by_key[key]
            if new == self.text(entry): raise ValueError('Replacement does not change text')
            index = len(self.pool) + list(additions).index(new) if new in additions else len(self.pool) + len(additions)
            additions[new] = additions.get(new, 0) + 1
            references[entry.string_index] -= 1
            struct.pack_into('<i', prefix, entry.index_offset, index)
        result = prefix + struct.pack('<i', len(self.pool) + len(additions))
        for raw, refs in zip(self.pool_raw, references):
            result += raw + struct.pack('<i', refs)
        for text, refs in additions.items():
            raw = text.encode('utf-16le') + b'\0\0'
            result += struct.pack('<i', -(len(raw) // 2)) + raw + struct.pack('<i', refs)
        candidate = Locres(bytes(result))
        for key, entry in self.by_key.items():
            other = candidate.by_key[key]
            if entry.source_hash != other.source_hash: raise ValueError('Source hash changed')
            expected = replacements.get(key, self.text(entry))
            if candidate.text(other) != expected: raise ValueError('Unexpected text change')
        return bytes(result)
