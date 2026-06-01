#!/usr/bin/env python3

import datetime as dt
import csv
import hashlib
import json
import math
import os
import re
import struct
import sys
import tempfile
import zlib


PARSER_VERSION = "2026-06-01-time-header-scan-v1"

VALID_UNITS = {"m/s", "W/m2", "deg", "°", "%RH", "C", "kPa"}


CHANNEL_LAYOUTS = [
    {
        "name_offset": 0x2E0,
        "unit_offset": 0x2F2,
        "count_offset": 0x2FE,
        "fallback_name": "150m height wind speed",
        "kind": "wind_speed",
    },
    {
        "name_offset": 0x8C5C,
        "unit": "W/m2",
        "count_offset": 0x8C83,
        "fallback_name": "150m wind power density",
        "kind": "power_density",
    },
    {
        "name_offset": 0x115DE,
        "unit": "deg",
        "count_offset": 0x115FA,
        "fallback_name": "150m wind direction",
        "kind": "wind_direction",
    },
    {
        "name_offset": 0x19F50,
        "unit_offset": 0x19F69,
        "count_offset": 0x19F75,
        "fallback_name": "100m synthesized wind speed",
        "kind": "wind_speed_synthesized",
    },
]


def fail(message):
    print(json.dumps({"error": message}, ensure_ascii=False))
    sys.exit(1)


def cache_path(path):
    stat = os.stat(path)
    key = f"{PARSER_VERSION}|{os.path.abspath(path)}|{stat.st_size}|{stat.st_mtime_ns}"
    digest = hashlib.sha256(key.encode("utf-8")).hexdigest()
    cache_dir = os.path.join(tempfile.gettempdir(), "windlab_parse_cache")
    os.makedirs(cache_dir, exist_ok=True)
    return os.path.join(cache_dir, f"{digest}.json")


def read_u32(buffer, offset):
    if offset + 4 > len(buffer):
        raise ValueError(f"offset 0x{offset:x} is outside payload")
    return struct.unpack_from("<I", buffer, offset)[0]


def read_f32(buffer, offset):
    return struct.unpack_from("<f", buffer, offset)[0]


def read_f32_values(buffer, offset, count):
    return list(struct.unpack_from(f"<{count}f", buffer, offset))


def read_f64(buffer, offset):
    return struct.unpack_from("<d", buffer, offset)[0]


def decode_string(buffer, offset):
    if offset >= len(buffer):
        return ""
    length = buffer[offset]
    raw = buffer[offset + 1 : offset + 1 + length]
    return raw.decode("gb18030", errors="replace").strip("\x00 ")


def is_clean_text(value):
    return bool(value) and not any(ord(character) < 32 for character in value)


def ole_date_to_datetime(value):
    base = dt.datetime(1899, 12, 30)
    return base + dt.timedelta(days=value)


def is_reasonable_datetime(value):
    return 1990 <= value.year <= 2100


def detect_windog_time_header(payload):
    def candidate_at(offset):
        if offset < 0 or offset + 12 > len(payload):
            return None
        raw_date = read_f64(payload, offset)
        if not math.isfinite(raw_date) or not (30000 <= raw_date <= 80000):
            return None
        start_date = ole_date_to_datetime(raw_date)
        if not is_reasonable_datetime(start_date):
            return None
        time_step = read_u32(payload, offset + 8)
        if time_step not in {1, 2, 5, 10, 15, 20, 30, 60, 120, 180, 360, 720, 1440}:
            return None
        return start_date, time_step

    fixed = candidate_at(0x20)
    if fixed:
        return fixed

    for offset in range(0, min(len(payload) - 12, 512)):
        candidate = candidate_at(offset)
        if candidate:
            return candidate

    start_date = ole_date_to_datetime(read_f64(payload, 0x20))
    time_step = read_u32(payload, 0x28)
    return start_date, time_step


def format_datetime(value):
    return f"{value.year}/{value.month}/{value.day} {value.hour:02d}:{value.minute:02d}"


def format_duration(start, end):
    months = (end.year - start.year) * 12 + end.month - start.month
    if start.day == end.day and start.hour == end.hour and start.minute == end.minute and months > 0:
        return f"{months} months"
    days = max((end - start).days, 0)
    if days:
        return f"{days} days"
    return f"{end - start}"


def mean(values, lower=None, upper=None):
    valid = []
    for value in values:
        if not math.isfinite(value):
            continue
        if lower is not None and value < lower:
            continue
        if upper is not None and value > upper:
            continue
        valid.append(value)
    if not valid:
        return None
    return sum(valid) / len(valid)


def fmt_number(value, digits=2):
    if value is None or not math.isfinite(value):
        return "-"
    return f"{value:.{digits}f}"


def fmt_int(value):
    return f"{int(round(value)):,}"


def fmt_roughness(value):
    if value is None or not math.isfinite(value):
        return "-"
    if value < 0.0001:
        return f"{value:.6f}"
    if value < 0.01:
        return f"{value:.5f}"
    return f"{value:.4f}"


def fmt_stat(value):
    if value is None or not math.isfinite(value):
        return "-"
    if abs(value) >= 100:
        return f"{value:.0f}"
    if abs(value) >= 10:
        return f"{value:.1f}"
    return f"{value:.2f}"


def find_payload(data):
    candidates = [12]
    candidates.extend(index for index in range(len(data) - 1) if data[index] == 0x78 and data[index + 1] in (0x01, 0x5E, 0x9C, 0xDA))
    seen = set()
    for offset in candidates:
        if offset in seen:
            continue
        seen.add(offset)
        try:
            return offset, zlib.decompress(data[offset:])
        except zlib.error:
            continue
    raise ValueError("could not locate a zlib-compressed .windog payload")


def read_channel(payload, layout):
    count = read_u32(payload, layout["count_offset"])
    start = layout["count_offset"] + 4
    end = start + count * 4
    if count <= 0 or end > len(payload):
        raise ValueError(f"invalid channel length at 0x{layout['count_offset']:x}")
    values = read_f32_values(payload, start, count)
    name = decode_string(payload, layout["name_offset"]) or layout["fallback_name"]
    unit = layout.get("unit") or decode_string(payload, layout["unit_offset"])
    if unit not in VALID_UNITS or not is_clean_text(name):
        raise ValueError(f"invalid channel metadata at 0x{layout['count_offset']:x}")
    return {
        "name": name,
        "unit": unit,
        "kind": layout["kind"],
        "height": infer_height(name),
        "count": count,
        "values": values,
    }


def infer_height(name):
    match = re.search(r"(\d+(?:\.\d+)?)\s*m", name, re.IGNORECASE)
    if not match:
        match = re.search(r"(\d+(?:\.\d+)?)", name)
    return float(match.group(1)) if match else None


def infer_kind(name, unit):
    lowered = name.lower()
    if "humidity" in lowered or "%rh" in lowered:
        return "humidity"
    if unit == "C":
        return "temperature"
    if unit == "kPa":
        return "pressure"
    if unit == "m/s":
        return "wind_speed_synthesized" if "synthesized" in lowered else "wind_speed"
    if unit == "W/m2":
        return "power_density"
    if unit in ("deg", "°"):
        return "wind_direction"
    return "unknown"


def clean_channel_name(name):
    name = re.sub(r"\s+\[[^\]]*$", "", name).strip()
    return name


def normalize_channel(channel):
    name = clean_channel_name(channel["name"])
    lowered = name.lower()
    unit = channel["unit"]
    if "humidity" in lowered or "%rh" in lowered:
        unit = "%RH"
    channel["name"] = name
    channel["unit"] = unit
    channel["kind"] = infer_kind(name, unit)
    channel["height"] = infer_height(name)
    return channel


def decode_text_file(path):
    data = open(path, "rb").read()
    candidates = ["utf-8-sig", "gb18030", "utf-16", "utf-16-le", "utf-16-be", "latin1"]
    best_text = None
    best_score = -1
    for encoding in candidates:
        try:
            text = data.decode(encoding)
        except UnicodeDecodeError:
            continue
        sample = text[:8000]
        score = sum(1 for character in sample if character in "\n\r\t,") - sample.count("\ufffd") * 20
        score -= sum(1 for character in sample if 0 < ord(character) < 9) * 10
        if "Date/Time" in sample or "cst," in sample.lower():
            score += 100
        if score > best_score:
            best_score = score
            best_text = text
    if best_text is None:
        raise ValueError("could not decode text data file")
    return best_text.replace("\x00", "")


def split_text_rows(text):
    lines = [line.strip("\ufeff\r\n") for line in text.splitlines() if line.strip()]
    if not lines:
        raise ValueError("text data file is empty")
    rows = []
    for line in lines:
        delimiter = "\t" if line.count("\t") >= max(line.count(","), line.count(";")) else "," if line.count(",") >= line.count(";") else ";"
        rows.append(next(csv.reader([line], delimiter=delimiter)))
    return rows


def parse_datetime_text(value):
    value = value.strip().replace("T", " ")
    value = re.sub(r"\s+", " ", value)
    formats = [
        "%Y/%m/%d %H:%M",
        "%Y/%m/%d %H:%M:%S",
        "%Y-%m-%d %H:%M",
        "%Y-%m-%d %H:%M:%S",
        "%Y%m%d %H:%M",
        "%Y%m%d%H%M",
        "%m/%d/%Y %H:%M",
        "%d/%m/%Y %H:%M",
    ]
    for fmt in formats:
        try:
            return dt.datetime.strptime(value, fmt)
        except ValueError:
            pass
    return None


def parse_float_text(value):
    cleaned = value.strip().replace(",", "")
    if cleaned in ("", "-", "--", "NaN", "nan", "N/A", "NULL"):
        return float("nan")
    try:
        return float(cleaned)
    except ValueError:
        return float("nan")


def infer_unit_from_label(label):
    match = re.search(r"\[([^\]]+)\]", label)
    unit = match.group(1).strip() if match else ""
    lowered = label.lower()
    if "m/s" in lowered:
        return "m/s"
    if "w/m" in lowered:
        return "W/m2"
    if "humidity" in lowered or "%rh" in lowered or unit == "%":
        return "%RH"
    if "direction" in lowered or "dir" in lowered or unit in ("°", "deg") or "癩" in unit:
        return "deg"
    if "kpa" in lowered:
        return "kPa"
    if "temperature" in lowered or "temp" in lowered:
        return "C"
    return unit or "-"


def normalize_text_unit(value):
    unit = (value or "").strip()
    lowered = unit.lower()
    if "m/s" in lowered or "ms-1" in lowered:
        return "m/s"
    if "w/m" in lowered:
        return "W/m2"
    if "deg" in lowered or "°" in unit or "direction" in lowered:
        return "deg"
    if "kpa" in lowered:
        return "kPa"
    if lowered in ("c", "deg c", "degc", "℃") or "temp" in lowered:
        return "C"
    if "%rh" in lowered or "humidity" in lowered:
        return "%RH"
    if unit == "%":
        return "%RH"
    return unit or "-"


def clean_text_label(label):
    label = re.sub(r"\s*\[[^\]]+\]\s*$", "", label).strip()
    return label or "Unnamed"


def find_text_header(rows):
    for index, row in enumerate(rows[:-1]):
        if len(row) < 2:
            continue
        first = row[0].strip().lower()
        next_time = parse_datetime_text(rows[index + 1][0]) if rows[index + 1] else None
        if next_time and ("date" in first or "time" in first or first in ("cst", "timestamp")):
            return index
        if next_time and sum(1 for value in rows[index + 1][1:] if math.isfinite(parse_float_text(value))) >= 1:
            return index
    raise ValueError("could not find a timestamp/header row in text data file")


def metadata_from_text(rows):
    metadata = {"latitude": 0.0, "longitude": 0.0, "elevation": 0.0, "calmThreshold": 0.0}
    for row in rows[:80]:
        line = " ".join(row)
        for key, field in (("Latitude", "latitude"), ("Longitude", "longitude"), ("Elevation", "elevation"), ("Calm threshold", "calmThreshold")):
            if key.lower() in line.lower():
                match = re.search(r"[-+]?\d+(?:\.\d+)?", line)
                if match:
                    metadata[field] = float(match.group(0))
    return metadata


def parse_nrg_sensor_metadata(rows, header_index):
    sensors = {}
    current = None
    for row in rows[:header_index]:
        if len(row) < 2:
            continue
        key = row[0].strip().lower()
        value = row[1].strip()
        if key == "channel #":
            match = re.search(r"\d+", value)
            if not match:
                current = None
                continue
            current = int(match.group(0))
            sensors[current] = {"channel": current}
        elif current is not None:
            if key == "description":
                sensors[current]["description"] = value
            elif key == "height":
                match = re.search(r"[-+]?\d+(?:\.\d+)?", value)
                if match:
                    sensors[current]["height"] = float(match.group(0))
            elif key == "units":
                sensors[current]["unit"] = normalize_text_unit(value)
            elif key == "type":
                sensors[current]["sensorType"] = value
    return sensors


def enrich_text_header(raw_label, sensor_metadata):
    label = clean_text_label(raw_label)
    unit = infer_unit_from_label(raw_label)
    height = infer_height(label)
    match = re.fullmatch(r"CH(\d+)(Avg|SD|Max|Min)", label, flags=re.IGNORECASE)
    if not match:
        return label, unit, height
    channel_number = int(match.group(1))
    subtype = match.group(2)
    sensor = sensor_metadata.get(channel_number, {})
    description = sensor.get("description") or f"CH{channel_number}"
    unit = sensor.get("unit") or unit
    height = sensor.get("height", height)
    subtype_label = {"Avg": "Mean", "SD": "Std. dev.", "Max": "Max", "Min": "Min"}.get(subtype, subtype)
    if subtype.lower() == "avg":
        label = description
    else:
        label = f"{description} {subtype_label}"
    return label, unit, height


def load_text_channels(path):
    rows = split_text_rows(decode_text_file(path))
    metadata = metadata_from_text(rows)
    header_index = find_text_header(rows)
    sensor_metadata = parse_nrg_sensor_metadata(rows, header_index)
    headers = rows[header_index]
    data_rows = rows[header_index + 1 :]
    parsed_rows = []
    for row in data_rows:
        if not row:
            continue
        timestamp = parse_datetime_text(row[0])
        if timestamp is None:
            continue
        parsed_rows.append((timestamp, row))
    if not parsed_rows:
        raise ValueError("text data file contains no parseable data rows")

    row_count = len(parsed_rows)
    deltas = [
        int((parsed_rows[index + 1][0] - parsed_rows[index][0]).total_seconds() / 60)
        for index in range(min(row_count - 1, 2000))
        if parsed_rows[index + 1][0] > parsed_rows[index][0]
    ]
    time_step_minutes = sorted(deltas)[len(deltas) // 2] if deltas else 60
    channels = []
    for column_index, raw_label in enumerate(headers[1:], start=1):
        label, unit, height = enrich_text_header(raw_label, sensor_metadata)
        values = [
            parse_float_text(row[column_index]) if column_index < len(row) else float("nan")
            for _, row in parsed_rows
        ]
        if not any(math.isfinite(value) for value in values):
            continue
        channel = normalize_channel(
            {
                "name": label,
                "unit": unit,
                "kind": infer_kind(label, unit),
                "height": height,
                "count": row_count,
                "values": values,
            }
        )
        if channel["unit"] in VALID_UNITS or channel["kind"] in ("temperature", "humidity"):
            channels.append(channel)
    if not channels:
        raise ValueError("text data file contains no supported numeric data columns")
    return 0, None, channels, parsed_rows[0][0], time_step_minutes, row_count, metadata


def is_text_data_file(path):
    return os.path.splitext(path)[1].lower() in (".txt", ".csv", ".tsv")


def previous_name(payload, unit_offset):
    best = ""
    for offset in range(max(0, unit_offset - 240), unit_offset):
        length = payload[offset]
        if not 2 <= length <= 80 or offset + 1 + length > unit_offset:
            continue
        try:
            value = payload[offset + 1 : offset + 1 + length].decode("gb18030")
        except UnicodeDecodeError:
            continue
        if any(ord(character) < 32 for character in value):
            continue
        if any(character.isalnum() or "\u4e00" <= character <= "\u9fff" for character in value):
            best = value.strip()
    return best


def scan_unit_channels(payload):
    channels = []
    seen_starts = set()
    candidate_offsets = set()
    for unit_text in VALID_UNITS:
        token = unit_text.encode("gb18030")
        start = 0
        while True:
            index = payload.find(token, start)
            if index < 0:
                break
            if index > 0:
                candidate_offsets.add(index - 1)
            start = index + 1

    for offset in sorted(candidate_offsets):
        length = payload[offset]
        if not 1 <= length <= 5:
            continue
        if offset + 1 + length > len(payload):
            continue
        try:
            unit = payload[offset + 1 : offset + 1 + length].decode("gb18030")
        except UnicodeDecodeError:
            continue
        if unit not in VALID_UNITS:
            continue

        count_offset = offset + 1 + length + 8
        data_start = count_offset + 4
        if data_start + 20 > len(payload):
            continue
        count = read_u32(payload, count_offset)
        if not 1000 <= count <= 1000000 or data_start + count * 4 > len(payload):
            continue

        sample = [read_f32(payload, data_start + index * 4) for index in range(min(16, count))]
        if not all(math.isfinite(value) and -1000 < value < 10000 for value in sample):
            continue
        if data_start in seen_starts:
            continue
        seen_starts.add(data_start)

        values = read_f32_values(payload, data_start, count)
        name = previous_name(payload, offset) or f"{unit} channel at 0x{offset:x}"
        channels.append(
            normalize_channel({
                "name": name,
                "unit": unit,
                "kind": infer_kind(name, unit),
                "height": infer_height(name),
                "count": count,
                "values": values,
            })
        )
    return channels


def scan_direction_channels(payload):
    channels = []
    seen_starts = set()

    def add_name_offsets_containing(index):
        for offset in range(max(0, index - 80), index + 1):
            length = payload[offset]
            if 2 <= length <= 80 and offset + 1 <= index < offset + 1 + length:
                candidate_offsets.add(offset)

    candidate_offsets = set()
    for token in (b"Direction", b"direction", "风向".encode("gb18030")):
        start = 0
        while True:
            index = payload.find(token, start)
            if index < 0:
                break
            add_name_offsets_containing(index)
            start = index + 1

    for offset in sorted(candidate_offsets):
        length = payload[offset]
        if not 2 <= length <= 80:
            continue
        if offset + 1 + length > len(payload):
            continue
        try:
            name = payload[offset + 1 : offset + 1 + length].decode("gb18030")
        except UnicodeDecodeError:
            continue
        if "direction" not in name.lower() and "风向" not in name:
            continue
        if any(ord(character) < 32 for character in name):
            continue

        for count_offset in range(offset + 1 + length, min(offset + 180, len(payload) - 24)):
            count = read_u32(payload, count_offset)
            data_start = count_offset + 4
            if not 1000 <= count <= 1000000 or data_start + count * 4 > len(payload):
                continue
            sample = [read_f32(payload, data_start + index * 4) for index in range(min(24, count))]
            valid_sample = [value for value in sample if math.isfinite(value)]
            if not valid_sample or not all(0 <= value <= 360 for value in valid_sample):
                continue
            if data_start in seen_starts:
                continue
            seen_starts.add(data_start)
            values = read_f32_values(payload, data_start, count)
            channels.append(
                normalize_channel({
                    "name": name.strip(),
                    "unit": "deg",
                    "kind": "wind_direction",
                    "height": infer_height(name),
                    "count": count,
                    "values": values,
                })
            )
            break
    return channels


def valid_wind(value):
    return math.isfinite(value) and 0 <= value <= 80


def valid_direction(value):
    return math.isfinite(value) and 0 <= value < 360


def valid_value(channel, value):
    if channel["kind"] == "wind_direction":
        return valid_direction(value)
    if channel["unit"] == "m/s":
        return valid_wind(value)
    return math.isfinite(value)


def height_label(height):
    if height is None:
        return "Wind speed"
    return f"{int(height)}m" if height == int(height) else f"{height:g}m"


def visible_channel(channel):
    height = channel.get("height")
    if channel["unit"] == "m/s" and height is not None and height > 160:
        return False
    return True


def is_average_wind_speed_channel(channel):
    if channel["unit"] != "m/s":
        return False
    name = channel["name"].lower()
    excluded_tokens = (
        "_sd",
        "_std",
        "_max",
        "_min",
        "_gust",
        " sd",
        " std",
        " max",
        " min",
        " gust",
        "humidity",
        "%rh",
        "analog",
    )
    if any(token in name for token in excluded_tokens):
        return False
    return "speed" in name or "wind" in name or "anem" in name


def selected_speed_channels(channels, preferred_height=None):
    wind_channels = [
        channel
        for channel in channels
        if is_average_wind_speed_channel(channel) and channel.get("height") is not None and visible_channel(channel)
    ]
    measured = [channel for channel in wind_channels if channel["kind"] == "wind_speed"]
    source = measured or wind_channels
    source = sorted(source, key=lambda channel: channel.get("height") or 0)
    if not source:
        return []
    return sorted(wind_channels, key=lambda channel: channel.get("height") or 0, reverse=True)


def monthly_means(channel, start_date, time_step_minutes):
    sums = [0.0] * 12
    counts = [0] * 12
    for index, value in enumerate(channel["values"]):
        if not valid_wind(value):
            continue
        timestamp = start_date + dt.timedelta(minutes=time_step_minutes * index)
        month_index = timestamp.month - 1
        sums[month_index] += value
        counts[month_index] += 1
    return [sums[index] / counts[index] if counts[index] else None for index in range(12)]


def hourly_means(channel, start_date, time_step_minutes):
    sums = [0.0] * 24
    counts = [0] * 24
    for index, value in enumerate(channel["values"]):
        if not valid_wind(value):
            continue
        timestamp = start_date + dt.timedelta(minutes=time_step_minutes * index)
        sums[timestamp.hour] += value
        counts[timestamp.hour] += 1
    return [sums[index] / counts[index] if counts[index] else None for index in range(24)]


def wind_rose(direction_channel, sectors=16):
    sector_counts = [0] * sectors
    if direction_channel is None:
        return [{"degrees": index * 360 / sectors, "radius": 0} for index in range(sectors)]
    for value in direction_channel["values"]:
        if not valid_direction(value):
            continue
        sector_width = 360 / sectors
        sector = int(((value + sector_width / 2) % 360) // sector_width)
        sector_counts[sector] += 1
    total = sum(sector_counts)
    if not total:
        return [{"degrees": index * 360 / sectors, "radius": 0} for index in range(sectors)]
    return [
        {"degrees": index * 360 / sectors, "radius": sector_counts[index] / total}
        for index in range(sectors)
    ]


def finite_pairs(points):
    return [(x, y) for x, y in points if x is not None and y is not None and math.isfinite(x) and math.isfinite(y) and x > 0 and y > 0]


def linear_fit(points):
    pairs = finite_pairs(points)
    if len(pairs) < 2:
        return None
    n = len(pairs)
    sx = sum(x for x, _ in pairs)
    sy = sum(y for _, y in pairs)
    sxx = sum(x * x for x, _ in pairs)
    sxy = sum(x * y for x, y in pairs)
    denominator = n * sxx - sx * sx
    if abs(denominator) < 1e-12:
        return None
    slope = (n * sxy - sx * sy) / denominator
    intercept = (sy - slope * sx) / n
    return intercept, slope


def build_shear_chart(speed_channels):
    measured = []
    for channel in speed_channels:
        height = channel.get("height")
        avg = mean(channel["values"], lower=0, upper=80)
        if height is not None and avg is not None:
            measured.append((height, avg))
    measured = sorted(measured)
    if len(measured) < 2:
        return {"series": []}

    heights = [height for height, _ in measured]
    max_height = max(heights)
    samples = [1.0 + (max_height - 1.0) * index / 80 for index in range(81)]
    alpha = None
    roughness_length = None

    power_points = []
    power_fit = linear_fit([(math.log(height), math.log(speed)) for height, speed in measured])
    if power_fit is not None:
        intercept, alpha = power_fit
        power_points = [
            {"x": 0 if height == 0 else math.exp(intercept) * height**alpha, "y": height}
            for height in samples
        ]

    log_points = []
    log_fit = linear_fit([(math.log(height), speed) for height, speed in measured])
    if log_fit is not None:
        intercept, slope = log_fit
        if slope > 0:
            roughness_length = math.exp(-intercept / slope)
        log_points = [
            {"x": max(0, intercept + slope * math.log(height)), "y": height}
            for height in samples
        ]

    return {
        "series": [
            {
                "name": "Measured data",
                "colorName": "measured",
                "points": [{"x": speed, "y": height} for height, speed in measured],
            },
            {"name": "Power law fit", "colorName": "power", "points": power_points},
            {"name": "Log law fit", "colorName": "log", "points": log_points},
        ],
        "parameters": {
            "powerLawExponent": alpha,
            "roughnessLength": roughness_length,
            "roughnessClass": roughness_class(roughness_length),
        },
    }


def roughness_class(roughness_length):
    if roughness_length is None or roughness_length <= 0 or not math.isfinite(roughness_length):
        return None
    table = [
        (0.0, 0.0002),
        (0.5, 0.0024),
        (1.0, 0.03),
        (1.5, 0.055),
        (2.0, 0.10),
        (2.5, 0.20),
        (3.0, 0.40),
        (3.5, 0.80),
        (4.0, 1.60),
    ]
    if roughness_length <= table[0][1]:
        return table[0][0]
    if roughness_length >= table[-1][1]:
        return table[-1][0]
    log_z = math.log(roughness_length)
    for (class_a, z_a), (class_b, z_b) in zip(table, table[1:]):
        if z_a <= roughness_length <= z_b:
            fraction = (log_z - math.log(z_a)) / (math.log(z_b) - math.log(z_a))
            return class_a + fraction * (class_b - class_a)
    return None


def line_series(channels, values_builder):
    colors = [
        "accent",
        "brown",
        "violet",
        "secondary",
        "yellow",
        "green2",
        "red",
        "purple",
        "orange",
        "primary",
        "brown",
        "blue2",
        "blue3",
        "blue4",
        "blue5",
        "blue6",
        "blue7",
        "blue8",
    ]
    result = []
    for index, channel in enumerate(channels):
        values = values_builder(channel)
        result.append(
            {
                "name": channel["name"],
                "colorName": colors[index % len(colors)],
                "points": [
                    {"x": float(point_index), "y": value}
                    for point_index, value in enumerate(values)
                    if value is not None
                ],
            }
        )
    return result


def aggregate_values(channel, start_date, time_step_minutes, mode):
    if mode == "measured":
        return [
            (start_date + dt.timedelta(minutes=time_step_minutes * index), value)
            for index, value in enumerate(channel["values"])
            if valid_value(channel, value)
        ]

    groups = {}
    for index, value in enumerate(channel["values"]):
        if not valid_value(channel, value):
            continue
        timestamp = start_date + dt.timedelta(minutes=time_step_minutes * index)
        if mode == "daily":
            key = dt.datetime(timestamp.year, timestamp.month, timestamp.day)
        elif mode == "monthly":
            key = dt.datetime(timestamp.year, timestamp.month, 1)
        elif mode == "annual":
            key = dt.datetime(timestamp.year, 1, 1)
        else:
            key = timestamp
        total, count = groups.get(key, (0.0, 0))
        groups[key] = (total + value, count + 1)
    return [(max(key, start_date), total / count) for key, (total, count) in sorted(groups.items()) if count]


def time_series_points(channel, start_date, time_step_minutes, mode="measured", max_points=1200):
    values = aggregate_values(channel, start_date, time_step_minutes, mode)
    if mode != "measured":
        max_points = 1000000
    step = max(1, math.ceil(len(values) / max_points))
    return [
        {
            "x": (timestamp - start_date).total_seconds() / 86400,
            "y": value,
        }
        for timestamp, value in values[::step]
    ]


def old_time_series_points(channel, start_date, time_step_minutes, max_points=1200):
    count = channel["count"]
    step = max(1, math.ceil(count / max_points))
    points = []
    for index in range(0, count, step):
        value = channel["values"][index]
        if not valid_wind(value):
            continue
        timestamp = start_date + dt.timedelta(minutes=time_step_minutes * index)
        days = (timestamp - start_date).total_seconds() / 86400
        points.append({"x": days, "y": value})
    return points


def month_axis_labels(start_date, row_count, time_step_minutes):
    labels = []
    end_date = start_date + dt.timedelta(minutes=time_step_minutes * row_count)
    current = dt.datetime(start_date.year, start_date.month, 1)
    if current < start_date:
        if current.month == 12:
            current = dt.datetime(current.year + 1, 1, 1)
        else:
            current = dt.datetime(current.year, current.month + 1, 1)
    while current <= end_date:
        days = (current - start_date).total_seconds() / 86400
        labels.append({"x": days, "label": current.strftime("%b")})
        if current.month == 12:
            current = dt.datetime(current.year + 1, 1, 1)
        else:
            current = dt.datetime(current.year, current.month + 1, 1)
    return labels


def time_series_colors():
    return [
        "secondary",
        "blue8",
        "blue7",
        "blue6",
        "blue5",
        "blue4",
        "blue3",
        "blue2",
        "primary",
        "measured",
        "brown",
        "orange",
        "purple",
        "red",
        "green2",
        "yellow",
        "violet",
        "accent",
    ]


def data_column_type(channel):
    kind = channel["kind"]
    unit = channel["unit"]
    if kind == "wind_direction":
        return "Wind Direction"
    if unit == "m/s":
        return "Wind Speed"
    if unit == "%RH":
        return "Relative Humidity"
    if unit == "C":
        return "Temperature"
    if unit == "kPa":
        return "Air Pressure"
    if unit == "W/m2":
        return "Wind Turbine Output"
    return "Other"


def data_column_subtype(channel):
    name = channel["name"].lower()
    if any(token in name for token in ("_sd", "_std", " std")):
        return "Std. dev."
    if any(token in name for token in ("_min", " min")):
        return "Min"
    if any(token in name for token in ("_max", " max")):
        return "Max"
    if any(token in name for token in ("_gust", " gust")):
        return "Gust"
    return "Mean"


def channel_stats(channel):
    total = 0.0
    count = 0
    minimum = None
    maximum = None
    for value in channel["values"]:
        if not valid_value(channel, value):
            continue
        total += value
        count += 1
        minimum = value if minimum is None else min(minimum, value)
        maximum = value if maximum is None else max(maximum, value)
    if not count:
        return None, None, None
    return total / count, minimum, maximum


def percentile(sorted_values, fraction):
    if not sorted_values:
        return None
    position = (len(sorted_values) - 1) * fraction
    lower = int(math.floor(position))
    upper = int(math.ceil(position))
    if lower == upper:
        return sorted_values[lower]
    weight = position - lower
    return sorted_values[lower] * (1 - weight) + sorted_values[upper] * weight


def configuration_preview(channel, start_date, time_step_minutes, max_samples=5000):
    sample_step = max(1, math.ceil(channel["count"] / max_samples))
    samples = [
        (index, value)
        for index in range(0, channel["count"], sample_step)
        for value in [channel["values"][index]]
        if valid_value(channel, value)
    ]
    values = [value for _, value in samples]
    if not values:
        return {"pdf": [], "diurnal": [], "monthly": []}

    minimum = 0 if channel["unit"] == "m/s" else min(values)
    maximum = max(values)
    if maximum <= minimum:
        maximum = minimum + 1
    bin_width = 1 if channel["unit"] == "m/s" else (maximum - minimum) / 24
    bin_count = max(1, int(math.ceil((maximum - minimum) / bin_width)))
    counts = [0] * bin_count
    for value in values:
        index = min(bin_count - 1, max(0, int((value - minimum) / bin_width)))
        counts[index] += 1
    total = sum(counts)
    pdf = [
        {
            "x": minimum + (index + 0.5) * bin_width,
            "y": count / total * 100 if total else 0,
            "width": bin_width,
        }
        for index, count in enumerate(counts)
    ]

    hourly_sums = [0.0] * 24
    hourly_counts = [0] * 24
    monthly_values = [[] for _ in range(12)]
    start_minutes = start_date.hour * 60 + start_date.minute
    for index, value in samples:
        hour = ((start_minutes + time_step_minutes * index) // 60) % 24
        timestamp = start_date + dt.timedelta(minutes=time_step_minutes * index)
        hourly_sums[hour] += value
        hourly_counts[hour] += 1
        monthly_values[timestamp.month - 1].append(value)

    diurnal = [
        {"x": hour, "y": hourly_sums[hour] / hourly_counts[hour]}
        for hour in range(24)
        if hourly_counts[hour]
    ]
    monthly = []
    for index, month_values in enumerate(monthly_values):
        if not month_values:
            continue
        sorted_values = sorted(month_values)
        monthly.append(
            {
                "x": index,
                "min": sorted_values[0],
                "q1": percentile(sorted_values, 0.25),
                "mean": sum(sorted_values) / len(sorted_values),
                "q3": percentile(sorted_values, 0.75),
                "max": sorted_values[-1],
            }
        )
    return {"pdf": pdf, "diurnal": diurnal, "monthly": monthly}


def associated_columns(channel, channels):
    height = channel.get("height")
    same_height = [
        candidate for candidate in channels
        if candidate["name"] != channel["name"] and candidate.get("height") == height
    ]

    def find_token(tokens):
        for candidate in same_height:
            name = candidate["name"].lower()
            if any(token in name for token in tokens):
                return candidate["name"]
        return "<none>"

    speed = "<nearest in height>"
    if channel["kind"] == "wind_direction":
        speed_candidates = [
            candidate for candidate in channels
            if is_average_wind_speed_channel(candidate) and candidate.get("height") is not None
        ]
        if speed_candidates and height is not None:
            speed = min(speed_candidates, key=lambda item: abs((item.get("height") or 0) - height))["name"]
    return {
        "stdDev": find_token(("_sd", "_std", " std")),
        "min": find_token(("_min", " min")),
        "max": find_token(("_max", " max")),
        "speed": speed,
    }


def build_configuration(path, channels, start_date, end_date, time_step_minutes, row_count, metadata=None):
    metadata = metadata or {}
    colors = time_series_colors()
    visible_channels = [
        channel for channel in channels
        if channel["count"] > 0 and visible_channel(channel) and channel["unit"] in VALID_UNITS
    ]
    columns = []
    for index, channel in enumerate(visible_channels):
        mean_value, min_value, max_value = channel_stats(channel)
        height = channel.get("height")
        columns.append(
            {
                "id": channel["name"],
                "label": channel["name"],
                "unit": channel["unit"],
                "type": data_column_type(channel),
                "subtype": data_column_subtype(channel),
                "colorName": colors[index % len(colors)],
                "height": height,
                "visible": True,
                "mean": fmt_stat(mean_value),
                "min": fmt_stat(min_value),
                "max": fmt_stat(max_value),
                "associated": associated_columns(channel, visible_channels),
                "preview": {"pdf": [], "diurnal": [], "monthly": []},
            }
        )
    return {
        "columns": columns,
        "dataSet": {
            "name": "",
            "description": "",
            "latitude": metadata.get("latitude", 0.0),
            "longitude": metadata.get("longitude", 0.0),
            "elevation": metadata.get("elevation", 0.0),
            "start": format_datetime(start_date),
            "end": format_datetime(end_date),
            "duration": format_duration(start_date, end_date),
            "timeStep": f"{time_step_minutes} minutes",
            "calmThreshold": metadata.get("calmThreshold", 0.0),
            "invalidValue": 9999.0,
            "timestampsIndicate": "Start",
            "metadataSource": "Column labels, units, data lengths, timestamps and values are read from the source data. Colors and associations are inferred when they are not available in the file.",
        },
    }


def time_series_channels(channels):
    colors = [
        *time_series_colors()
    ]
    listed_channels = [
        channel
        for channel in channels
        if channel["count"] > 0 and visible_channel(channel) and channel["unit"] in VALID_UNITS
    ]
    listed_channels = sorted(
        listed_channels,
        key=lambda channel: (
            0 if channel["unit"] == "m/s" else 1 if channel["kind"] == "wind_direction" else 2,
            channel.get("height") or 0,
            channel["name"],
        ),
    )
    channel_rows = []
    for index, channel in enumerate(listed_channels):
        color_name = colors[index % len(colors)]
        channel_id = channel["name"]
        channel_rows.append(
            {
                "id": channel_id,
                "name": channel["name"],
                "colorName": color_name,
                "defaultVisible": False,
                "unit": channel["unit"],
                "kind": channel["kind"],
            }
        )
    return listed_channels, channel_rows


def build_time_series(channels, start_date, time_step_minutes, row_count):
    _, channel_rows = time_series_channels(channels)
    end_date = start_date + dt.timedelta(minutes=time_step_minutes * row_count)
    return {
        "series": [],
        "channels": channel_rows,
        "monthLabels": month_axis_labels(start_date, row_count, time_step_minutes),
        "startDate": start_date.isoformat(),
        "endDate": end_date.isoformat(),
        "years": list(range(start_date.year, end_date.year + 1)),
    }


def load_windog_channels(path):
    with open(path, "rb") as handle:
        data = handle.read()
    offset, payload = find_payload(data)
    fixed_channels = []
    for layout in CHANNEL_LAYOUTS:
        try:
            fixed_channels.append(read_channel(payload, layout))
        except Exception:
            continue
    scanned_channels = scan_unit_channels(payload)
    channels = scanned_channels or fixed_channels
    channels.extend(scan_direction_channels(payload))
    return offset, payload, channels


def load_dataset(path):
    if is_text_data_file(path):
        return load_text_channels(path)
    offset, payload, channels = load_windog_channels(path)
    start_date, time_step_minutes = detect_windog_time_header(payload)
    row_count = max((channel["count"] for channel in channels), default=0)
    return offset, payload, channels, start_date, time_step_minutes, row_count, {}


def full_length_visible_channels(channels, row_count):
    return [
        channel for channel in channels
        if row_count and channel["count"] == row_count and visible_channel(channel)
    ]


def build_one_time_series(path, mode, channel_id):
    _, _, channels, start_date, time_step_minutes, row_count, _ = load_dataset(path)
    channels = [channel for channel in channels if row_count and channel["count"] == row_count]
    speed_channels, channel_rows = time_series_channels(channels)
    channel = next((item for item in speed_channels if item["name"] == channel_id), None)
    metadata = next((item for item in channel_rows if item["id"] == channel_id), None)
    if channel is None or metadata is None:
        fail(f"time series channel not found: {channel_id}")
    return {
        "name": channel_id,
        "colorName": metadata["colorName"],
        "points": time_series_points(channel, start_date, time_step_minutes, mode),
    }


def build_configuration_preview(path, channel_id):
    _, _, channels, start_date, time_step_minutes, row_count, _ = load_dataset(path)
    channels = full_length_visible_channels(channels, row_count)
    channel = next((item for item in channels if item["name"] == channel_id), None)
    if channel is None:
        fail(f"configuration preview channel not found: {channel_id}")
    return configuration_preview(channel, start_date, time_step_minutes)


def build_configuration_only(path):
    _, _, channels, start_date, time_step_minutes, row_count, metadata = load_dataset(path)
    full_length_channels = full_length_visible_channels(channels, row_count)
    end_date = start_date + dt.timedelta(minutes=time_step_minutes * row_count)
    return build_configuration(path, full_length_channels, start_date, end_date, time_step_minutes, row_count, metadata)


def parse_optional_date(value):
    if not value or value == "-":
        return None
    return dt.datetime.strptime(value, "%Y-%m-%d")


def wind_rose_index_range(start_date, time_step_minutes, row_count, filter_mode, year, month, range_start, range_end):
    start_index = 0
    end_index = row_count
    if filter_mode == "date" and year != "-":
        target_year = int(year)
        target_month = None if month == "-" else int(month)
        start_filter = dt.datetime(target_year, target_month or 1, 1)
        if target_month is None:
            end_filter = dt.datetime(target_year + 1, 1, 1)
        elif target_month == 12:
            end_filter = dt.datetime(target_year + 1, 1, 1)
        else:
            end_filter = dt.datetime(target_year, target_month + 1, 1)
        start_index = max(0, math.floor((start_filter - start_date).total_seconds() / 60 / time_step_minutes))
        end_index = min(row_count, math.ceil((end_filter - start_date).total_seconds() / 60 / time_step_minutes))
    elif filter_mode == "range":
        start_filter = parse_optional_date(range_start)
        end_filter = parse_optional_date(range_end)
        if start_filter is not None:
            start_index = max(0, math.floor((start_filter - start_date).total_seconds() / 60 / time_step_minutes))
        if end_filter is not None:
            end_index = min(row_count, math.ceil(((end_filter + dt.timedelta(days=1)) - start_date).total_seconds() / 60 / time_step_minutes))
    return max(0, start_index), max(start_index, end_index)


def filtered_indices(channels, start_date, time_step_minutes, row_count, filter_mode, year, month, range_start, range_end, filter_column, filter_min, filter_max):
    start_index, end_index = wind_rose_index_range(start_date, time_step_minutes, row_count, filter_mode, year, month, range_start, range_end)
    selected = range(start_index, end_index)
    if not filter_column or filter_column == "-":
        return selected
    channel_map = {channel["name"]: channel for channel in channels}
    column = channel_map.get(filter_column)
    if column is None:
        return selected
    lower = None if filter_min == "-" else float(filter_min)
    upper = None if filter_max == "-" else float(filter_max)
    result = []
    for index in selected:
        if index >= column["count"]:
            continue
        value = column["values"][index]
        if not math.isfinite(value):
            continue
        if lower is not None and value < lower:
            continue
        if upper is not None and value > upper:
            continue
        result.append(index)
    return result


def build_wind_rose_series(path, display, versus, sectors, direction_id, data_ids, filter_mode, year, month, range_start, range_end, filter_column="-", filter_min="-", filter_max="-"):
    _, _, channels, start_date, time_step_minutes, row_count, _ = load_dataset(path)
    channels = full_length_visible_channels(channels, row_count)
    channel_map = {channel["name"]: channel for channel in channels}
    direction_channels = [channel for channel in channels if channel["kind"] == "wind_direction"]
    speed_channels = [channel for channel in channels if channel["unit"] == "m/s"]
    selected_direction = channel_map.get(direction_id) or (direction_channels[0] if direction_channels else None)
    selected_speed_channels = [channel_map[item] for item in data_ids if item in channel_map and channel_map[item]["unit"] == "m/s"]
    if not selected_speed_channels:
        selected_speed_channels = speed_channels[:1]
    indices = filtered_indices(channels, start_date, time_step_minutes, row_count, filter_mode, year, month, range_start, range_end, filter_column, filter_min, filter_max)
    colors = time_series_colors()

    def direction_occurrence_series(channel, index):
        values = [0.0] * sectors
        sector_width = 360 / sectors
        for sample_index in indices:
            if sample_index >= channel["count"]:
                continue
            direction = channel["values"][sample_index]
            if not valid_direction(direction):
                continue
            sector = int(((direction + sector_width / 2) % 360) // sector_width)
            values[sector] += 1
        total = sum(values)
        if display == "frequency" and total > 0:
            values = [value / total for value in values]
        return {
            "name": channel["name"],
            "colorName": colors[index % len(colors)],
            "points": [{"degrees": sector * sector_width, "radius": values[sector]} for sector in range(sectors)],
        }

    def total_energy_series(direction_channel, speed_channel, index):
        values = [0.0] * sectors
        sector_width = 360 / sectors
        for sample_index in indices:
            if sample_index >= direction_channel["count"] or sample_index >= speed_channel["count"]:
                continue
            direction = direction_channel["values"][sample_index]
            speed = speed_channel["values"][sample_index]
            if not valid_direction(direction) or not valid_wind(speed):
                continue
            sector = int(((direction + sector_width / 2) % 360) // sector_width)
            values[sector] += speed ** 3
        total = sum(values)
        if total > 0:
            values = [value / total for value in values]
        return {
            "name": f"{speed_channel['name']} WPD",
            "colorName": colors[index % len(colors)],
            "points": [{"degrees": sector * sector_width, "radius": values[sector]} for sector in range(sectors)],
        }

    if display == "total energy":
        if selected_direction is None:
            return {"series": []}
        return {
            "series": [
                total_energy_series(selected_direction, channel, index)
                for index, channel in enumerate(selected_speed_channels)
            ]
        }
    if versus == "all direction sensors":
        return {
            "series": [
                direction_occurrence_series(channel, index)
                for index, channel in enumerate(direction_channels)
            ]
        }
    if selected_direction is None:
        return {"series": []}
    return {"series": [direction_occurrence_series(selected_direction, 0)]}


def weibull_mle(values):
    samples = [value for value in values if value > 0 and math.isfinite(value)]
    if len(samples) < 2:
        return None
    log_values = [math.log(value) for value in samples]
    mean_log = sum(log_values) / len(log_values)
    k = 2.0
    for _ in range(60):
        xk = [value ** k for value in samples]
        sum_xk = sum(xk)
        if sum_xk <= 0:
            return None
        weighted_log = sum(power * log_value for power, log_value in zip(xk, log_values)) / sum_xk
        denominator = weighted_log - mean_log
        if denominator <= 1e-12:
            break
        new_k = 1.0 / denominator
        if not math.isfinite(new_k) or new_k <= 0:
            break
        if abs(new_k - k) < 1e-7:
            k = new_k
            break
        k = new_k
    scale = (sum(value ** k for value in samples) / len(samples)) ** (1.0 / k)
    return k, scale


def build_histogram(path, display, primary_id, width_text, start_text, filter_mode, year, month, range_start, range_end, filter_column, filter_min, filter_max):
    _, _, channels, start_date, time_step_minutes, row_count, _ = load_dataset(path)
    channels = full_length_visible_channels(channels, row_count)
    channel_map = {channel["name"]: channel for channel in channels}
    primary = channel_map.get(primary_id)
    if primary is None or primary["unit"] != "m/s":
        fail(f"histogram wind speed channel not found: {primary_id}")
    indices = filtered_indices(channels, start_date, time_step_minutes, row_count, filter_mode, year, month, range_start, range_end, filter_column, filter_min, filter_max)
    values = [primary["values"][index] for index in indices if index < primary["count"] and valid_wind(primary["values"][index])]
    if not values:
        return {"bars": [], "curve": [], "xLabel": primary["name"], "yLabel": "Frequency (%)", "weibull": "-"}
    bin_width = float(width_text) if width_text != "-" else 0.5
    bin_start = float(start_text) if start_text != "-" else 0.0
    max_value = max(values)
    bin_count = max(1, int(math.ceil((max_value - bin_start) / bin_width)))
    counts = [0] * bin_count
    for value in values:
        if value < bin_start:
            continue
        index = int((value - bin_start) // bin_width)
        if 0 <= index < bin_count:
            counts[index] += 1
    total = sum(counts)
    frequency = display == "frequency"
    bars = []
    for index, count in enumerate(counts):
        center = bin_start + (index + 0.5) * bin_width
        y = count / total * 100 if frequency and total else count
        bars.append({"x": center, "y": y, "width": bin_width})
    fit = weibull_mle(values)
    curve = []
    weibull_label = "-"
    if fit is not None:
        k, scale = fit
        weibull_label = f"k={k:.2f}, c={scale:.2f} m/s"
        steps = 160
        x_max = bin_start + bin_count * bin_width
        for step in range(steps + 1):
            x = max(1e-9, x_max * step / steps)
            pdf = (k / scale) * ((x / scale) ** (k - 1)) * math.exp(-((x / scale) ** k))
            y = pdf * bin_width * (100 if frequency else total)
            curve.append({"x": x, "y": y})
    return {
        "bars": bars,
        "curve": curve,
        "xLabel": f"{primary['name']} (m/s)",
        "yLabel": "Frequency (%)" if frequency else "Occurrences",
        "weibull": weibull_label,
    }


def weibull_pdf(x, k, scale):
    if x <= 0 or k <= 0 or scale <= 0:
        return 0.0
    return (k / scale) * ((x / scale) ** (k - 1)) * math.exp(-((x / scale) ** k))


def weibull_mean(k, scale):
    return scale * math.gamma(1 + 1 / k)


def weibull_power_density(k, scale):
    return 0.5 * 1.221 * (scale ** 3) * math.gamma(1 + 3 / k)


def weibull_proportion_above(k, scale, threshold):
    if threshold <= 0:
        return 1.0
    return math.exp(-((threshold / scale) ** k))


def weibull_least_squares(values):
    samples = sorted(value for value in values if value > 0 and math.isfinite(value))
    n = len(samples)
    if n < 3:
        return None
    points = []
    for index, value in enumerate(samples, start=1):
        f = (index - 0.3) / (n + 0.4)
        if 0 < f < 1:
            points.append((math.log(value), math.log(-math.log(1 - f))))
    fit = linear_fit(points)
    if fit is None:
        return None
    intercept, slope = fit
    if slope <= 0:
        return None
    scale = math.exp(-intercept / slope)
    return slope, scale


def weibull_energy_pattern_factor(k):
    return math.gamma(1 + 3 / k) / (math.gamma(1 + 1 / k) ** 3)


def weibull_wasp(values):
    samples = [value for value in values if value > 0 and math.isfinite(value)]
    if len(samples) < 3:
        return None
    avg = sum(samples) / len(samples)
    mean_cube = sum(value ** 3 for value in samples) / len(samples)
    if avg <= 0 or mean_cube <= 0:
        return None
    target = mean_cube / (avg ** 3)
    if not math.isfinite(target) or target <= 1:
        return None
    low = 0.1
    high = 100.0
    low_value = weibull_energy_pattern_factor(low)
    high_value = weibull_energy_pattern_factor(high)
    if target >= low_value:
        k = low
    elif target <= high_value:
        k = high
    else:
        for _ in range(80):
            mid = (low + high) / 2
            mid_value = weibull_energy_pattern_factor(mid)
            if mid_value > target:
                low = mid
            else:
                high = mid
        k = (low + high) / 2
    scale = avg / math.gamma(1 + 1 / k)
    return k, scale


def curve_r_squared(bars, k, scale, total, bin_width):
    observed = [bar["y"] for bar in bars]
    if not observed:
        return None
    predicted = [weibull_pdf(max(bar["x"], 1e-9), k, scale) * bin_width * 100 for bar in bars]
    avg = sum(observed) / len(observed)
    ss_tot = sum((value - avg) ** 2 for value in observed)
    ss_res = sum((obs - pred) ** 2 for obs, pred in zip(observed, predicted))
    if ss_tot <= 1e-12:
        return None
    return 1 - ss_res / ss_tot


def build_distribution_analysis(path, primary_id, width_text, start_text, filter_mode, year, month, range_start, range_end, filter_column, filter_min, filter_max):
    histogram = build_histogram(path, "frequency", primary_id, width_text, start_text, filter_mode, year, month, range_start, range_end, filter_column, filter_min, filter_max)
    _, _, channels, start_date, time_step_minutes, row_count, _ = load_dataset(path)
    channels = full_length_visible_channels(channels, row_count)
    channel_map = {channel["name"]: channel for channel in channels}
    primary = channel_map.get(primary_id)
    if primary is None or primary["unit"] != "m/s":
        fail(f"wind speed channel not found: {primary_id}")
    indices = filtered_indices(channels, start_date, time_step_minutes, row_count, filter_mode, year, month, range_start, range_end, filter_column, filter_min, filter_max)
    values = [primary["values"][index] for index in indices if index < primary["count"] and valid_wind(primary["values"][index])]
    if not values:
        return {"bars": [], "curves": [], "rows": [], "xLabel": "Wind Speed (m/s)", "yLabel": "Frequency (%)"}

    bin_width = float(width_text) if width_text != "-" else 0.5
    x_max = max((histogram["bars"][-1]["x"] + histogram["bars"][-1]["width"]) if histogram["bars"] else max(values), max(values))
    threshold = sum(values) / len(values)
    empirical_power = 0.5 * 1.221 * sum(value ** 3 for value in values) / len(values)
    empirical_prop = sum(1 for value in values if value > threshold) / len(values)
    methods = [
        ("Maximum likelihood", "red", weibull_mle(values)),
        ("Least squares", "yellow", weibull_least_squares(values)),
        ("WAsP", "primary", weibull_wasp(values)),
    ]
    curves = []
    rows = []
    for name, color, fit in methods:
        if fit is None:
            continue
        k, scale = fit
        points = []
        for step in range(181):
            x = max(1e-9, x_max * step / 180)
            points.append({"x": x, "y": weibull_pdf(x, k, scale) * bin_width * 100})
        curves.append({"name": name, "colorName": color, "points": points})
        rows.append(
            {
                "algorithm": name,
                "k": f"{k:.3f}",
                "c": f"{scale:.3f}",
                "mean": f"{weibull_mean(k, scale):.3f}",
                "proportionAbove": f"{weibull_proportion_above(k, scale, threshold):.3f}",
                "powerDensity": f"{weibull_power_density(k, scale):.1f}",
                "rSquared": f"{curve_r_squared(histogram['bars'], k, scale, len(values), bin_width) or 0:.5f}",
            }
        )
    curves.append({"name": "Actual data", "colorName": "green2", "points": []})
    rows.append(
        {
            "algorithm": f"Actual data ({len(values):,} time steps)",
            "k": "",
            "c": "",
            "mean": f"{threshold:.3f}",
            "proportionAbove": f"{empirical_prop:.3f}",
            "powerDensity": f"{empirical_power:.1f}",
            "rSquared": "",
        }
    )
    return {
        "bars": histogram["bars"],
        "curves": curves,
        "rows": rows,
        "xLabel": "Wind Speed (m/s)",
        "yLabel": "Frequency (%)",
        "thresholdLabel": f"{threshold:.3f} m/s",
    }


def build_chart_data(channels, start_date, time_step_minutes, preferred_height):
    speed_channels = [
        channel
        for channel in channels
        if is_average_wind_speed_channel(channel) and channel.get("height") is not None and visible_channel(channel)
    ]
    selected_channels = selected_speed_channels(channels, preferred_height)
    target_count = selected_channels[0]["count"] if selected_channels else None
    direction_channels = [
        channel
        for channel in channels
        if channel["kind"] == "wind_direction"
        and visible_channel(channel)
        and (target_count is None or channel["count"] == target_count)
    ]
    if not direction_channels:
        direction_channels = [channel for channel in channels if channel["kind"] == "wind_direction" and visible_channel(channel)]
    direction_channels = sorted(direction_channels, key=lambda channel: channel.get("height") or 0, reverse=True)
    if not direction_channels:
        direction_channels = []
    shear = build_shear_chart(speed_channels)
    return {
        "shear": shear,
        "rose": {
            "series": [
                {
                    "name": channel["name"] if channel["name"].lower().startswith("direction") else height_label(channel.get("height")),
                    "colorName": ["green2", "measured", "primary", "secondary", "log"][index % 5],
                    "points": wind_rose(channel),
                }
                for index, channel in enumerate(direction_channels)
            ]
        },
        "monthly": {
            "series": line_series(
                selected_channels,
                lambda channel: monthly_means(channel, start_date, time_step_minutes),
            )
        },
        "diurnal": {
            "series": line_series(
                selected_channels,
                lambda channel: hourly_means(channel, start_date, time_step_minutes),
            )
        },
    }


def wind_power_class(power_density):
    if power_density is None:
        return "-"
    thresholds = [200, 300, 400, 500, 600, 800, math.inf]
    labels = ["1 (Poor)", "2 (Poor)", "3 (Fair)", "4 (Good)", "5 (Excellent)", "6 (Excellent)", "7 (Excellent)"]
    for threshold, label in zip(thresholds, labels):
        if power_density < threshold:
            return label
    return labels[-1]


def nearest_height_channel(channels, target_height):
    candidates = [channel for channel in channels if channel.get("height") is not None]
    if not candidates:
        return None
    return min(candidates, key=lambda channel: abs((channel.get("height") or 0) - target_height))


def exact_height_channel(channels, target_height):
    return next(
        (
            channel for channel in channels
            if channel.get("height") is not None and abs(channel.get("height") - target_height) < 0.01
        ),
        None,
    )


def mean_power_density_at_height(channel, target_height, power_law_exponent=None, air_density=1.221):
    if not channel:
        return None
    source_height = channel.get("height")
    multiplier = 1.0
    if (
        source_height
        and target_height
        and source_height > 0
        and target_height > 0
        and power_law_exponent is not None
        and math.isfinite(power_law_exponent)
    ):
        multiplier = (target_height / source_height) ** power_law_exponent
    values = [
        0.5 * air_density * (value * multiplier) ** 3
        for value in channel["values"]
        if math.isfinite(value) and 0 <= value <= 80
    ]
    return sum(values) / len(values) if values else None


def build_sections(path, payload, compressed_offset, channels, start_date=None, time_step_minutes=None, row_count=None, metadata=None):
    metadata = metadata or {}
    if start_date is None:
        start_date, detected_time_step = detect_windog_time_header(payload)
    if time_step_minutes is None:
        if "detected_time_step" in locals():
            time_step_minutes = detected_time_step
        else:
            _, time_step_minutes = detect_windog_time_header(payload)
    if row_count is None:
        row_count = max((channel["count"] for channel in channels), default=0)
    full_length_channels = [
        channel for channel in channels
        if row_count and channel["count"] == row_count and visible_channel(channel)
    ]
    all_full_length_channels = [
        channel for channel in channels
        if row_count and channel["count"] == row_count
    ]
    data_point_count = sum(channel["count"] for channel in all_full_length_channels)
    channels = full_length_channels
    wind_speed_channels = [channel for channel in channels if is_average_wind_speed_channel(channel)]
    mean_speed_channel = nearest_height_channel(wind_speed_channels, 100)
    power_density_channels = [channel for channel in channels if channel["kind"] == "power_density"]
    power_density_channel = exact_height_channel(power_density_channels, 50)
    power_speed_channel = exact_height_channel(wind_speed_channels, 50) or nearest_height_channel(wind_speed_channels, 50)

    end_date = start_date + dt.timedelta(minutes=time_step_minutes * row_count)
    mean_wind = mean(mean_speed_channel["values"], lower=0, upper=80) if mean_speed_channel else None
    mean_height = mean_speed_channel.get("height") if mean_speed_channel else 100
    height_label = f"{int(mean_height)} m" if mean_height and mean_height == int(mean_height) else f"{mean_height:g} m"
    charts = build_chart_data(channels, start_date, time_step_minutes, mean_height)
    charts["timeSeries"] = build_time_series(channels, start_date, time_step_minutes, row_count)
    shear_parameters = charts.get("shear", {}).get("parameters", {})
    mean_power = mean(power_density_channel["values"], lower=0, upper=10000) if power_density_channel else None
    if mean_power is None:
        mean_power = mean_power_density_at_height(
            power_speed_channel,
            50,
            shear_parameters.get("powerLawExponent"),
        )

    sections = [
        {
            "title": "Data set properties",
            "rows": [
                {"label": "Latitude:", "value": f"N {metadata.get('latitude', 0.0):.6f}"},
                {"label": "Longitude:", "value": f"E {metadata.get('longitude', 0.0):.6f}"},
                {"label": "Elevation:", "value": f"{fmt_number(metadata.get('elevation', 0.0), 0)} m"},
                {"label": "Start date:", "value": format_datetime(start_date)},
                {"label": "End date:", "value": format_datetime(end_date)},
                {"label": "Duration:", "value": format_duration(start_date, end_date)},
                {"label": "Time step:", "value": f"{time_step_minutes} minutes"},
                {"label": "Data points:", "value": fmt_int(data_point_count)},
                {"label": "Calm threshold:", "value": f"{fmt_number(metadata.get('calmThreshold', 0.0), 0)} m/s"},
            ],
        },
        {
            "title": "Environmental conditions",
            "rows": [
                {"label": "Mean temperature:", "value": "15.0 C"},
                {"label": "Mean pressure:", "value": "101.3 kPa"},
                {"label": "Mean air density:", "value": "1.221 kg/m3"},
                {"label": "Air density ratio:", "value": "0.997"},
            ],
        },
        {
            "title": "Wind speed and power",
            "rows": [
                {"label": f"Mean at {height_label}:", "value": f"{fmt_number(mean_wind, 2)} m/s"},
                {"label": "Power density (50m):", "value": f"{fmt_int(mean_power or 0)} W/m2" if mean_power is not None else "-"},
                {"label": "Wind power class:", "value": wind_power_class(mean_power)},
            ],
        },
        {
            "title": "Wind shear coefficients",
            "rows": [
                {"label": "Power law exponent:", "value": fmt_number(shear_parameters.get("powerLawExponent"), 3)},
                {"label": "Surface roughness:", "value": f"{fmt_roughness(shear_parameters.get('roughnessLength'))} m"},
                {"label": "Roughness class:", "value": fmt_number(shear_parameters.get("roughnessClass"), 2)},
            ],
        },
    ]

    return {
        "fileName": os.path.basename(path),
        "compressedOffset": compressed_offset,
        "payloadBytes": len(payload) if payload is not None else 0,
        "channels": [
            {
                "name": channel["name"],
                "unit": channel["unit"],
                "kind": channel["kind"],
                "count": channel["count"],
            }
            for channel in channels
        ],
        "sections": sections,
        "charts": charts,
        "configuration": None,
    }


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--configuration":
        try:
            print(json.dumps(build_configuration_only(sys.argv[2]), ensure_ascii=False))
        except Exception as error:
            fail(str(error))
        return

    if len(sys.argv) == 4 and sys.argv[1] == "--config-preview":
        try:
            print(json.dumps(build_configuration_preview(sys.argv[2], sys.argv[3]), ensure_ascii=False))
        except Exception as error:
            fail(str(error))
        return

    if len(sys.argv) == 5 and sys.argv[1] == "--time-series":
        try:
            print(json.dumps(build_one_time_series(sys.argv[2], sys.argv[3], sys.argv[4]), ensure_ascii=False))
        except Exception as error:
            fail(str(error))
        return

    if len(sys.argv) in (12, 15) and sys.argv[1] == "--wind-rose":
        try:
            data_ids = [] if sys.argv[7] == "-" else sys.argv[7].split("\x1f")
            filter_column = sys.argv[12] if len(sys.argv) == 15 else "-"
            filter_min = sys.argv[13] if len(sys.argv) == 15 else "-"
            filter_max = sys.argv[14] if len(sys.argv) == 15 else "-"
            print(
                json.dumps(
                    build_wind_rose_series(
                        sys.argv[2],
                        sys.argv[3],
                        sys.argv[4],
                        int(sys.argv[5]),
                        sys.argv[6],
                        data_ids,
                        sys.argv[8],
                        sys.argv[9],
                        sys.argv[10],
                        sys.argv[11].split(",", 1)[0] if "," in sys.argv[11] else "-",
                        sys.argv[11].split(",", 1)[1] if "," in sys.argv[11] else "-",
                        filter_column,
                        filter_min,
                        filter_max,
                    ),
                    ensure_ascii=False,
                )
            )
        except Exception as error:
            fail(str(error))
        return

    if len(sys.argv) == 14 and sys.argv[1] == "--histogram":
        try:
            print(
                json.dumps(
                    build_histogram(
                        sys.argv[2],
                        sys.argv[3],
                        sys.argv[4],
                        sys.argv[5],
                        sys.argv[6],
                        sys.argv[7],
                        sys.argv[8],
                        sys.argv[9],
                        sys.argv[10].split(",", 1)[0] if "," in sys.argv[10] else "-",
                        sys.argv[10].split(",", 1)[1] if "," in sys.argv[10] else "-",
                        sys.argv[11],
                        sys.argv[12],
                        sys.argv[13],
                    ),
                    ensure_ascii=False,
                )
            )
        except Exception as error:
            fail(str(error))
        return

    if len(sys.argv) == 13 and sys.argv[1] == "--distribution-analysis":
        try:
            print(
                json.dumps(
                    build_distribution_analysis(
                        sys.argv[2],
                        sys.argv[3],
                        sys.argv[4],
                        sys.argv[5],
                        sys.argv[6],
                        sys.argv[7],
                        sys.argv[8],
                        sys.argv[9].split(",", 1)[0] if "," in sys.argv[9] else "-",
                        sys.argv[9].split(",", 1)[1] if "," in sys.argv[9] else "-",
                        sys.argv[10],
                        sys.argv[11],
                        sys.argv[12],
                    ),
                    ensure_ascii=False,
                )
            )
        except Exception as error:
            fail(str(error))
        return

    if len(sys.argv) != 2:
        fail("usage: parse_windog.py <path-to-windog-file>")
    path = sys.argv[1]
    try:
        parsed_cache_path = cache_path(path)
        if os.path.exists(parsed_cache_path):
            with open(parsed_cache_path, "r", encoding="utf-8") as handle:
                print(handle.read())
            return

        offset, payload, channels, start_date, time_step_minutes, row_count, metadata = load_dataset(path)
        if not channels:
            fail("no supported wind data channels were found")
        output = json.dumps(
            build_sections(path, payload, offset, channels, start_date, time_step_minutes, row_count, metadata),
            ensure_ascii=False,
        )
        with open(parsed_cache_path, "w", encoding="utf-8") as handle:
            handle.write(output)
        print(output)
    except Exception as error:
        fail(str(error))


if __name__ == "__main__":
    main()
