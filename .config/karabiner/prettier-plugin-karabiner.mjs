// prettier-plugin-karabiner.mjs
//
// Formats JSON exactly like Karabiner-Elements' json_writer, which uses
// pqrs::json::pqrs_formatter with indent_size=4 and a fixed set of
// force_multi_line_array_object_keys:
//   https://github.com/pqrs-org/cpp-json/blob/main/include/pqrs/json/pqrs_formatter.hpp
//   https://github.com/pqrs-org/Karabiner-Elements/blob/main/src/share/json_utility.hpp
//
// Structural rules (never width-based):
//   object: empty -> "{}" ; 1 key  -> single-line iff the value is single-line ;
//           >1 keys -> multi-line
//   array : forced keys    -> always multi-line ;
//           empty -> "[]" ; 1 elem -> single-line iff the element is single-line ;
//           >1 elems -> multi-line iff any element is an object/array
//   single-line object: { "key": value }   (spaces inside braces)
//   single-line array:  [a, b]             (no spaces inside brackets)
//
// Values are serialized like nlohmann::json::dump(): strings escape only
// C0 controls and " \ (raw UTF-8 passes through), numbers keep their raw
// lexeme so e.g. `1.0` stays `1.0`.

const INDENT_SIZE = 4;

const FORCE_MULTI_LINE_ARRAY_OBJECT_KEYS = new Set([
  'bundle_identifiers',
  'description_notes',
  'game_pad_stick_horizontal_wheel_formula',
  'game_pad_stick_vertical_wheel_formula',
  'game_pad_stick_x_formula',
  'game_pad_stick_y_formula',
]);

// ---------------------------------------------------------------------------
// Minimal JSON parser. Objects keep ordered [key, value] entries so key
// order and numeric lexemes survive verbatim.
// ---------------------------------------------------------------------------

function isObj(v) {
  return typeof v === 'object' && v !== null && !Array.isArray(v) && v.entries !== undefined;
}
function isNum(v) {
  return typeof v === 'object' && v !== null && !Array.isArray(v) && v.num !== undefined;
}

function parseJSON(text) {
  let i = 0;
  const n = text.length;

  function fail(msg) {
    throw new SyntaxError(`karabiner-json parse error: ${msg} at offset ${i}`);
  }

  function ws() {
    while (i < n && (text[i] === ' ' || text[i] === '\t' || text[i] === '\n' || text[i] === '\r')) i++;
  }

  function parseStringRaw() {
    // text[i] === '"'
    i++;
    let out = '';
    while (i < n) {
      const ch = text[i];
      if (ch === '"') {
        i++;
        return out;
      }
      if (ch === '\\') {
        i++;
        if (i >= n) fail('truncated escape');
        const esc = text[i++];
        switch (esc) {
          case '"':
            out += '"';
            break;
          case '\\':
            out += '\\';
            break;
          case '/':
            out += '/';
            break;
          case 'b':
            out += '\b';
            break;
          case 'f':
            out += '\f';
            break;
          case 'n':
            out += '\n';
            break;
          case 'r':
            out += '\r';
            break;
          case 't':
            out += '\t';
            break;
          case 'u': {
            if (i + 4 > n) fail('truncated \\u escape');
            const hi = parseInt(text.substr(i, 4), 16);
            i += 4;
            if (hi >= 0xd800 && hi <= 0xdbff && text[i] === '\\' && text[i + 1] === 'u' && i + 6 <= n) {
              const lo = parseInt(text.substr(i + 2, 4), 16);
              if (lo >= 0xdc00 && lo <= 0xdfff) {
                i += 6;
                out += String.fromCodePoint(0x10000 + ((hi - 0xd800) << 10) + (lo - 0xdc00));
                break;
              }
            }
            out += String.fromCharCode(hi);
            break;
          }
          default:
            fail(`invalid escape \\${esc}`);
        }
      } else {
        out += ch;
        i++;
      }
    }
    fail('unterminated string');
  }

  function parseNumber() {
    const start = i;
    if (text[i] === '-') i++;
    if (text[i] === '0') {
      i++;
    } else if (text[i] >= '1' && text[i] <= '9') {
      while (i < n && text[i] >= '0' && text[i] <= '9') i++;
    } else {
      fail('invalid number');
    }
    if (text[i] === '.') {
      i++;
      if (!(text[i] >= '0' && text[i] <= '9')) fail('invalid number');
      while (i < n && text[i] >= '0' && text[i] <= '9') i++;
    }
    if (text[i] === 'e' || text[i] === 'E') {
      i++;
      if (text[i] === '+' || text[i] === '-') i++;
      if (!(text[i] >= '0' && text[i] <= '9')) fail('invalid number');
      while (i < n && text[i] >= '0' && text[i] <= '9') i++;
    }
    return { num: text.slice(start, i) };
  }

  function parseArray() {
    // text[i] === '['
    i++;
    const items = [];
    ws();
    if (text[i] === ']') {
      i++;
      return items;
    }
    for (;;) {
      items.push(parseValue());
      ws();
      if (text[i] === ',') {
        i++;
        ws();
      } else if (text[i] === ']') {
        i++;
        return items;
      } else {
        fail('expected , or ] in array');
      }
    }
  }

  function parseObject() {
    // text[i] === '{'
    i++;
    const entries = [];
    ws();
    if (text[i] === '}') {
      i++;
      return { entries };
    }
    for (;;) {
      ws();
      if (text[i] !== '"') fail('expected object key');
      const key = parseStringRaw();
      ws();
      if (text[i] !== ':') fail('expected : in object');
      i++;
      const value = parseValue();
      entries.push([key, value]);
      ws();
      if (text[i] === ',') {
        i++;
      } else if (text[i] === '}') {
        i++;
        return { entries };
      } else {
        fail('expected , or } in object');
      }
    }
  }

  function parseValue() {
    ws();
    if (i >= n) fail('unexpected end of input');
    const c = text[i];
    if (c === '{') return parseObject();
    if (c === '[') return parseArray();
    if (c === '"') return parseStringRaw();
    if (text.startsWith('true', i)) {
      i += 4;
      return true;
    }
    if (text.startsWith('false', i)) {
      i += 5;
      return false;
    }
    if (text.startsWith('null', i)) {
      i += 4;
      return null;
    }
    return parseNumber();
  }

  const value = parseValue();
  ws();
  if (i !== n) fail('trailing characters');
  return value;
}

// ---------------------------------------------------------------------------
// Serialization matching nlohmann::json::dump(ensure_ascii=false)
// ---------------------------------------------------------------------------

function quoteString(s) {
  let out = '"';
  for (let k = 0; k < s.length; k++) {
    const code = s.charCodeAt(k);
    switch (code) {
      case 0x22:
        out += '\\"';
        break;
      case 0x5c:
        out += '\\\\';
        break;
      case 0x08:
        out += '\\b';
        break;
      case 0x09:
        out += '\\t';
        break;
      case 0x0a:
        out += '\\n';
        break;
      case 0x0c:
        out += '\\f';
        break;
      case 0x0d:
        out += '\\r';
        break;
      default:
        if (code < 0x20) {
          out += '\\u' + code.toString(16).padStart(4, '0');
        } else {
          out += s[k];
        }
    }
  }
  return out + '"';
}

// Keys are emitted with std::quoted in Karabiner's writer: only `"` and `\`
// are escaped. Equivalent to quoteString for every key that occurs in
// practice, but kept separate for faithfulness.
function quoteKey(s) {
  return '"' + s.replace(/\\/g, '\\\\').replace(/"/g, '\\"') + '"';
}

// ---------------------------------------------------------------------------
// pqrs_formatter layout rules
// ---------------------------------------------------------------------------

function isMultiLine(value, parentKey) {
  if (isObj(value)) {
    const { entries } = value;
    if (entries.length === 0) return false;
    if (entries.length === 1) return isMultiLine(entries[0][1], entries[0][0]);
    return true;
  }
  if (Array.isArray(value)) {
    if (parentKey != null && FORCE_MULTI_LINE_ARRAY_OBJECT_KEYS.has(parentKey)) return true;
    if (value.length === 0) return false;
    if (value.length === 1) return isMultiLine(value[0], null);
    return value.some((item) => isObj(item) || Array.isArray(item));
  }
  return false;
}

function indent(level) {
  return ' '.repeat(INDENT_SIZE * level);
}

function formatValue(value, parentKey, level) {
  if (isObj(value)) {
    const { entries } = value;
    if (!isMultiLine(value, parentKey)) {
      if (entries.length === 0) return '{}';
      const [k, v] = entries[0];
      return '{ ' + quoteKey(k) + ': ' + formatValue(v, k, level + 1) + ' }';
    }
    const body = entries.map(([k, v]) => indent(level + 1) + quoteKey(k) + ': ' + formatValue(v, k, level + 1));
    return '{\n' + body.join(',\n') + '\n' + indent(level) + '}';
  }
  if (Array.isArray(value)) {
    if (!isMultiLine(value, parentKey)) {
      return '[' + value.map((v) => formatValue(v, null, level + 1)).join(', ') + ']';
    }
    const body = value.map((v) => indent(level + 1) + formatValue(v, null, level + 1));
    return '[\n' + body.join(',\n') + '\n' + indent(level) + ']';
  }
  if (value === null) return 'null';
  if (value === true) return 'true';
  if (value === false) return 'false';
  if (isNum(value)) return value.num;
  return quoteString(value);
}

// ---------------------------------------------------------------------------
// Prettier plugin plumbing
// ---------------------------------------------------------------------------

export const languages = [
  {
    name: 'karabiner-json',
    parsers: ['karabiner-json'],
  },
];

export const parsers = {
  'karabiner-json': {
    parse: (text) => parseJSON(text),
    astFormat: 'karabiner-json-ast',
    locStart: () => 0,
    locEnd: () => 0,
  },
};

export const printers = {
  'karabiner-json-ast': {
    print: (path) => formatValue(path.getValue(), null, 0),
  },
};
