# Static verification for the rebuilt Swift project (no Swift toolchain on this machine).
# Checks: ghost APIs, brace/paren balance (strings & comments stripped), @main placement,
# type/member cross-references, custom type definitions, key API signatures.
import re
import glob
import json
import collections

issues = []


def ok(msg):
    print(f"  [PASS] {msg}")


def fail(msg):
    print(f"  [FAIL] {msg}")
    issues.append(msg)


swift_files = sorted(
    f for f in glob.glob('**/*.swift', recursive=True)
    if not f.replace(chr(92), '/').startswith(('preview/', 'Tests/', '.build/', '.zcode/'))
)
all_swift = {f.replace(chr(92), '/'): open(f, encoding='utf-8').read() for f in swift_files}

STRING_RE = re.compile(r'"(?:\\.|[^"\\])*"')
LINE_COMMENT_RE = re.compile(r'//[^\n]*')
BLOCK_COMMENT_RE = re.compile(r'/\*.*?\*/', re.S)


def strip_strings_comments(src):
    # Order matters: strip string literals first so that "//" inside a string
    # (e.g. "https://...") is not mistaken for a line comment.
    src = STRING_RE.sub('""', src)
    src = LINE_COMMENT_RE.sub('', src)
    src = BLOCK_COMMENT_RE.sub('', src)
    return src


print("=== A. Ghost API residue (old symbols must be gone) ===")
ghosts = ['detectedPitchHz', 'detectedOctave', 'centsOffset', 'isTargetMatched', 'setTarget(note',
          'toggleListening', 'toggleContinuousPlay', 'ScaleType', 'currentBPM',
          'SynthToneGenerator', 'ScalePlayerEngine', 'PitchTrackerLiveView', 'ScalePlayerView',
          'ChallengeView', 'WaveformBarView', 'ProgressViewDashboard', 'RoutineStage', 'ShortsTip']
for g in ghosts:
    hits = [(f, i + 1) for f, src in all_swift.items() for i, line in enumerate(src.splitlines()) if g in line]
    fail(f"{g} residue: {hits}") if hits else ok(f"{g} absent")

print()
print("=== B. Brace/paren balance after stripping strings & comments ===")
bad = 0
for f, src in sorted(all_swift.items()):
    s = strip_strings_comments(src)
    if s.count('{') != s.count('}'):
        fail(f"{f}: braces {s.count('{')}/{s.count('}')}")
        bad += 1
    elif s.count('(') != s.count(')'):
        fail(f"{f}: parens {s.count('(')}/{s.count(')')}")
        bad += 1
ok(f"{len(all_swift)} files checked, {bad} unbalanced")

print()
print("=== C. @main placement (comments stripped) ===")
for f, n in [('HaruVocalApp.swift', 1), ('Widget/VocalWidgetBundle.swift', 1)]:
    s = strip_strings_comments(all_swift[f])
    if len(re.findall(r'@main', s)) != n:
        fail(f"{f} @main count != {n}")
ok("exactly one @main in app entry and one in widget bundle")

print()
print("=== D. Type member cross-references ===")


def type_body(src, name):
    m = re.search(r'(?:final\s+)?(?:class|struct)\s+' + name + r'\b', src)
    if not m:
        return None
    depth = 0
    started = False
    out = []
    for ch in src[m.start():]:
        if ch == '{':
            depth += 1
            started = True
        elif ch == '}':
            depth -= 1
        if started:
            out.append(ch)
        if started and depth == 0:
            break
    return ''.join(out)


def members(body):
    names = set()
    for pat in [r'func\s+([a-zA-Z_][a-zA-Z0-9_]*)',
                r'(?:var|let)\s+([a-zA-Z_][a-zA-Z0-9_]*)',
                r'case\s+([a-zA-Z_][a-zA-Z0-9_]*)']:
        names.update(re.findall(pat, body))
    return names


types = ['VocalAudioEngine', 'ScaleSequencer', 'DailyRoutineViewModel', 'PitchTrackerViewModel',
         'ProgressViewModel', 'VocalLabViewModel', 'YINPitchDetector', 'NotificationManager',
         'LiveActivityManager']
defs = {}
for t in types:
    body = None
    for f, src in all_swift.items():
        b = type_body(strip_strings_comments(src), t)
        if b:
            body = b
    if body is None:
        fail(f"{t} definition not found")
        continue
    defs[t] = members(body)
    print(f"  {t}: {len(defs[t])} members defined")

ctx = {
    'Views/DailyRoutine/DailyRoutineView.swift': {'viewModel': 'DailyRoutineViewModel', 'sequencer': 'ScaleSequencer'},
    'Views/DailyRoutine/StepDetailCard.swift': {'audio': 'VocalAudioEngine', 'sequencer': 'ScaleSequencer'},
    'Views/PitchTracker/PitchTrackerView.swift': {'viewModel': 'PitchTrackerViewModel', 'audio': 'VocalAudioEngine'},
    'Views/Progress/VocalProgressView.swift': {'viewModel': 'ProgressViewModel'},
    'Views/Onboarding/OnboardingView.swift': {'audio': 'VocalAudioEngine'},
    'ViewModels/DailyRoutineViewModel.swift': {'audio': 'VocalAudioEngine', 'sequencer': 'ScaleSequencer'},
    'ViewModels/PitchTrackerViewModel.swift': {'audio': 'VocalAudioEngine'},
    'ViewModels/ProgressViewModel.swift': {'audio': 'VocalAudioEngine'},
}
checked = 0
for f, mapping in ctx.items():
    src = strip_strings_comments(all_swift.get(f, ''))
    for inst, cls in mapping.items():
        for m in re.finditer(r'\b' + re.escape(inst) + r'\.([a-zA-Z_][a-zA-Z0-9_]*)', src):
            member = m.group(1)
            if member in defs.get(cls, set()):
                checked += 1
            else:
                fail(f"{f}: {inst}.{member} not defined on {cls}")
ok(f"{checked} instance-member references all resolve")

print()
print("=== E. Custom type definitions ===")
all_src = chr(10).join(strip_strings_comments(s) for s in all_swift.values())
custom_types = ['DailyRoutineView', 'PitchTrackerView', 'VocalLabView', 'VocalProgressView', 'OnboardingView',
                'MainTabView', 'StepDetailCard', 'TipDetailView', 'HeatmapCalendarView', 'VocalRangeChart',
                'PitchLineCanvas', 'LiveNoteDisplay', 'PianoStrip', 'GuideNoteBadge', 'LiveFeedbackIndicator',
                'RangeTestModel', 'RangeTestPage', 'RoutineStep', 'RoutinePresets', 'TonePatternType',
                'VocalCategory', 'VocalTip', 'UserProfile', 'PracticeSession', 'PitchRecord', 'PitchEstimate',
                'YINPitchDetector', 'VocalAudioEngine', 'ScaleSequencer', 'HapticManager', 'LiveActivityManager',
                'VocalActivityAttributes', 'NotificationManager', 'PitchPoint', 'HeatmapDay',
                'DailyRoutineViewModel', 'PitchTrackerViewModel', 'ProgressViewModel', 'VocalLabViewModel',
                'VocalLiveActivityWidget', 'VocalWidgetBundle', 'HaruVocalApp', 'GlassCard',
                'GlassCardModifier']
missing = [t for t in custom_types if not re.search(r'\b(?:class|struct|enum)\s+' + t + r'\b', all_src)]
fail(f"missing definitions: {missing}") if missing else ok(f"all {len(custom_types)} custom types defined")

print()
print("=== F. Key API signatures ===")
engine = all_swift['Core/Audio/VocalAudioEngine.swift']
yin = all_swift['Core/Logic/YINPitchDetector.swift']
widget = all_swift['Widget/VocalWidgetBundle.swift']
checks = [
    ('vDSP_vsub(base, 1, base + tau, 1, &diff, 1, vDSP_Length(window))' in yin, 'vDSP_vsub 8-arg call'),
    ('vDSP_svesq(diff, 1, &sumOfSquares, vDSP_Length(window))' in yin, 'vDSP_svesq call'),
    ('vDSP_rmsqv(channel, 1, &rms, vDSP_Length(frameLength))' in engine, 'vDSP_rmsqv call'),
    ('AVAudioApplication.requestRecordPermission' in engine, 'iOS 17 permission API'),
    ('scheduleBuffer(buffer)' in engine, 'tone scheduling'),
    ('timerInterval: context.state.stepStartTime...context.state.stepEndTime' in widget, 'widget timer interval'),
]
for cond, name in checks:
    ok(name) if cond else fail(name)

print()
print("=== G. vocal_tips.json <-> VocalTip Codable consistency ===")
tips = json.load(open('Resources/vocal_tips.json', encoding='utf-8'))
required = {'id', 'category', 'title', 'shortsSummary', 'beginnerAnalogy', 'howTo', 'youtubeId',
            'viewCount', 'relatedShorts', 'keyActionWord'}
cat_raw = {'breathing', 'falsetto_switch', 'sound_direction', 'jaw_larynx', 'nasal_resonance', 'practical_tips'}
for t in tips:
    if set(t.keys()) != required:
        fail(f"field mismatch id={t['id']}")
    if t['category'] not in cat_raw:
        fail(f"bad category id={t['id']}")
ids = {t['id'] for t in tips}
for t in tips:
    for r in t['relatedShorts']:
        if r not in ids or r == t['id']:
            fail(f"invalid relatedShorts id={t['id']}->{r}")
ok(f"{len(tips)} tips; fields/categories/relatedShorts consistent")
for field in ['beginnerAnalogy', 'howTo', 'keyActionWord', 'shortsSummary']:
    dups = [k for k, v in collections.Counter(t[field] for t in tips).items() if v > 1]
    ok(f"{field}: {len(dups)} duplicates") if not dups else fail(f"{field} duplicated: {dups}")
dist = dict(collections.Counter(t['category'] for t in tips))
ok(f"category distribution: {dist}")
same = sum(1 for t in tips for r in t['relatedShorts']
           if next(x for x in tips if x['id'] == r)['category'] == t['category'])
total = sum(len(t['relatedShorts']) for t in tips)
ok(f"same-category relatedShorts: {same}/{total}")

print()
print("=" * 60)
if issues:
    print(f"RESULT: {len(issues)} FAILURES")
    for i in issues:
        print(f"  - {i}")
    raise SystemExit(1)
print("RESULT: ALL CHECKS PASSED")
