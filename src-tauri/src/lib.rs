use enigo::{
  Axis, Button as EnigoButton, Coordinate, Direction, Enigo, Mouse, Settings,
};
use rdev::{listen, Button as RdevButton, Event, EventType};
use serde::{Deserialize, Serialize};
use std::{
  sync::{
    atomic::{AtomicBool, Ordering},
    Arc, Mutex,
  },
  thread,
  time::{Duration, Instant},
};

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
  tauri::Builder::default()
    .manage(AutomationState::default())
    .invoke_handler(tauri::generate_handler![
      start_auto_click,
      stop_auto_click,
      start_recording,
      stop_recording,
      playback_script,
      automation_status
    ])
    .setup(|app| {
      if cfg!(debug_assertions) {
        app.handle().plugin(
          tauri_plugin_log::Builder::default()
            .level(log::LevelFilter::Info)
            .build(),
        )?;
      }
      Ok(())
    })
    .run(tauri::generate_context!())
    .expect("error while running tauri application");
}

struct AutomationState {
  status: Arc<Mutex<AutomationStatus>>,
  click_stop: Mutex<Option<Arc<AtomicBool>>>,
  playback_stop: Mutex<Option<Arc<AtomicBool>>>,
  recording: Arc<AtomicBool>,
  listener_started: AtomicBool,
  recorded_steps: Arc<Mutex<Vec<ScriptStep>>>,
  recording_anchor: Arc<Mutex<Option<Instant>>>,
  last_event_at: Arc<Mutex<Option<Instant>>>,
  last_mouse_position: Arc<Mutex<Option<(i32, i32)>>>,
}

impl Default for AutomationState {
  fn default() -> Self {
    Self {
      status: Arc::new(Mutex::new(AutomationStatus::default())),
      click_stop: Mutex::new(None),
      playback_stop: Mutex::new(None),
      recording: Arc::new(AtomicBool::new(false)),
      listener_started: AtomicBool::new(false),
      recorded_steps: Arc::new(Mutex::new(Vec::new())),
      recording_anchor: Arc::new(Mutex::new(None)),
      last_event_at: Arc::new(Mutex::new(None)),
      last_mouse_position: Arc::new(Mutex::new(None)),
    }
  }
}

#[derive(Clone, Serialize)]
struct AutomationStatus {
  running: bool,
  mode: String,
  last_action: String,
}

impl Default for AutomationStatus {
  fn default() -> Self {
    Self {
      running: false,
      mode: "idle".to_string(),
      last_action: "ready".to_string(),
    }
  }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ClickConfig {
  interval_ms: u64,
  button: String,
  repeat: u32,
}

#[derive(Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct ScriptStep {
  id: Option<String>,
  kind: String,
  label: Option<String>,
  x: Option<i32>,
  y: Option<i32>,
  button: Option<String>,
  duration_ms: Option<u64>,
}

#[tauri::command]
fn start_auto_click(
  state: tauri::State<'_, AutomationState>,
  config: ClickConfig,
) -> Result<AutomationStatus, String> {
  stop_worker(&state.click_stop)?;

  let interval_ms = config.interval_ms.max(50);
  let repeat = config.repeat;
  let button = parse_button(&config.button);
  let stop_flag = Arc::new(AtomicBool::new(false));
  *state.click_stop.lock().map_err(lock_error)? = Some(stop_flag.clone());

  thread::spawn(move || {
    let Ok(mut enigo) = Enigo::new(&Settings::default()) else {
      return;
    };
    let mut count = 0;
    while !stop_flag.load(Ordering::SeqCst) && (repeat == 0 || count < repeat) {
      let _ = enigo.button(button, Direction::Click);
      count += 1;
      sleep_interruptibly(Duration::from_millis(interval_ms), &stop_flag);
    }
  });

  set_status(
    &state,
    true,
    "auto-click",
    format!(
      "interval={}ms button={} repeat={}",
      interval_ms, config.button, repeat
    ),
  )
}

#[tauri::command]
fn stop_auto_click(state: tauri::State<'_, AutomationState>) -> Result<AutomationStatus, String> {
  stop_worker(&state.click_stop)?;
  stop_worker(&state.playback_stop)?;
  set_status(&state, false, "idle", "stopped")
}

#[tauri::command]
fn start_recording(state: tauri::State<'_, AutomationState>) -> Result<AutomationStatus, String> {
  state.recording.store(true, Ordering::SeqCst);
  state.recorded_steps.lock().map_err(lock_error)?.clear();
  *state.recording_anchor.lock().map_err(lock_error)? = Some(Instant::now());
  *state.last_event_at.lock().map_err(lock_error)? = None;
  ensure_recording_listener(&state);
  set_status(&state, true, "recording", "recording mouse events")
}

#[tauri::command]
fn stop_recording(state: tauri::State<'_, AutomationState>) -> Result<Vec<ScriptStep>, String> {
  state.recording.store(false, Ordering::SeqCst);
  set_status(&state, false, "idle", "recording stopped")?;
  state
    .recorded_steps
    .lock()
    .map(|steps| steps.clone())
    .map_err(lock_error)
}

#[tauri::command]
fn playback_script(
  state: tauri::State<'_, AutomationState>,
  steps: Vec<ScriptStep>,
) -> Result<AutomationStatus, String> {
  stop_worker(&state.playback_stop)?;

  let stop_flag = Arc::new(AtomicBool::new(false));
  *state.playback_stop.lock().map_err(lock_error)? = Some(stop_flag.clone());
  let queued = steps.len();
  let first = steps
    .first()
    .map(describe_step)
    .unwrap_or_else(|| "empty script".to_string());

  thread::spawn(move || {
    let Ok(mut enigo) = Enigo::new(&Settings::default()) else {
      return;
    };
    for step in steps {
      if stop_flag.load(Ordering::SeqCst) {
        break;
      }
      let _ = run_step(&mut enigo, &step);
    }
  });

  set_status(
    &state,
    true,
    "playback",
    format!("{} steps queued, first: {}", queued, first),
  )
}

#[tauri::command]
fn automation_status(state: tauri::State<'_, AutomationState>) -> Result<AutomationStatus, String> {
  state
    .status
    .lock()
    .map(|status| status.clone())
    .map_err(lock_error)
}

fn ensure_recording_listener(state: &AutomationState) {
  if state
    .listener_started
    .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
    .is_err()
  {
    return;
  }

  let recording = state.recording.clone();
  let steps = state.recorded_steps.clone();
  let anchor = state.recording_anchor.clone();
  let last_event_at = state.last_event_at.clone();
  let last_mouse_position = state.last_mouse_position.clone();

  thread::spawn(move || {
    let callback = move |event: Event| {
      if !recording.load(Ordering::SeqCst) {
        return;
      }
      if let Some(step) = event_to_step(event, &anchor, &last_event_at, &last_mouse_position) {
        if let Ok(mut recorded_steps) = steps.lock() {
          recorded_steps.push(step);
        }
      }
    };

    if let Err(error) = listen(callback) {
      log::error!("mouse recording listener failed: {:?}", error);
    }
  });
}

fn event_to_step(
  event: Event,
  anchor: &Arc<Mutex<Option<Instant>>>,
  last_event_at: &Arc<Mutex<Option<Instant>>>,
  last_mouse_position: &Arc<Mutex<Option<(i32, i32)>>>,
) -> Option<ScriptStep> {
  let now = Instant::now();
  let elapsed_ms = anchor
    .lock()
    .ok()
    .and_then(|start| start.map(|instant| now.duration_since(instant).as_millis() as u64))
    .unwrap_or_default();

  let wait_ms = {
    let mut last = last_event_at.lock().ok()?;
    let wait = last
      .map(|instant| now.duration_since(instant).as_millis() as u64)
      .unwrap_or_default();
    *last = Some(now);
    wait
  };

  let make_step = |kind: &str, label: String, x: Option<i32>, y: Option<i32>, button: Option<String>, duration_ms: Option<u64>| {
    Some(ScriptStep {
      id: Some(format!("recorded-{}-{}", elapsed_ms, kind)),
      kind: kind.to_string(),
      label: Some(label),
      x,
      y,
      button,
      duration_ms,
    })
  };

  if wait_ms > 120 {
    return make_step(
      "wait",
      format!("等待 {}ms", wait_ms),
      None,
      None,
      None,
      Some(wait_ms),
    );
  }

  match event.event_type {
    EventType::MouseMove { x, y } => {
      let x = x.round() as i32;
      let y = y.round() as i32;
      let mut last_position = last_mouse_position.lock().ok()?;
      let should_record = last_position
        .map(|(last_x, last_y)| (last_x - x).abs() + (last_y - y).abs() > 12)
        .unwrap_or(true);
      *last_position = Some((x, y));
      if should_record {
        make_step("move", "移动鼠标".to_string(), Some(x), Some(y), None, Some(80))
      } else {
        None
      }
    }
    EventType::ButtonPress(button) => {
      let (x, y) = last_mouse_position
        .lock()
        .ok()
        .and_then(|position| *position)
        .unwrap_or_default();
      let button = rdev_button_name(button);
      make_step(
        "click",
        format!("{}键点击", button_label(&button)),
        Some(x),
        Some(y),
        Some(button),
        None,
      )
    }
    EventType::Wheel { delta_y, .. } => make_step(
      "scroll",
      "滚动滚轮".to_string(),
      None,
      None,
      None,
      Some(delta_y.unsigned_abs().max(1)),
    ),
    _ => None,
  }
}

fn run_step(enigo: &mut Enigo, step: &ScriptStep) -> Result<(), String> {
  match step.kind.as_str() {
    "move" => {
      if let (Some(x), Some(y)) = (step.x, step.y) {
        enigo
          .move_mouse(x, y, Coordinate::Abs)
          .map_err(|error| error.to_string())?;
      }
      sleep_step(step);
      Ok(())
    }
    "click" => {
      if let (Some(x), Some(y)) = (step.x, step.y) {
        enigo
          .move_mouse(x, y, Coordinate::Abs)
          .map_err(|error| error.to_string())?;
      }
      enigo
        .button(parse_button(step.button.as_deref().unwrap_or("left")), Direction::Click)
        .map_err(|error| error.to_string())
    }
    "wait" => {
      sleep_step(step);
      Ok(())
    }
    "scroll" => {
      let amount = step.duration_ms.unwrap_or(3).clamp(1, 20) as i32;
      enigo
        .scroll(amount, Axis::Vertical)
        .map_err(|error| error.to_string())?;
      Ok(())
    }
    other => Err(format!("unknown script step kind: {}", other)),
  }
}

fn sleep_step(step: &ScriptStep) {
  if let Some(duration_ms) = step.duration_ms {
    thread::sleep(Duration::from_millis(duration_ms));
  }
}

fn sleep_interruptibly(duration: Duration, stop_flag: &AtomicBool) {
  let chunk = Duration::from_millis(25);
  let mut slept = Duration::ZERO;
  while slept < duration && !stop_flag.load(Ordering::SeqCst) {
    let remaining = duration.saturating_sub(slept);
    let current = remaining.min(chunk);
    thread::sleep(current);
    slept += current;
  }
}

fn stop_worker(worker: &Mutex<Option<Arc<AtomicBool>>>) -> Result<(), String> {
  if let Some(stop_flag) = worker.lock().map_err(lock_error)?.take() {
    stop_flag.store(true, Ordering::SeqCst);
  }
  Ok(())
}

fn set_status(
  state: &AutomationState,
  running: bool,
  mode: impl Into<String>,
  last_action: impl Into<String>,
) -> Result<AutomationStatus, String> {
  let mut status = state.status.lock().map_err(lock_error)?;
  status.running = running;
  status.mode = mode.into();
  status.last_action = last_action.into();
  Ok(status.clone())
}

fn parse_button(button: &str) -> EnigoButton {
  match button {
    "right" => EnigoButton::Right,
    "middle" => EnigoButton::Middle,
    _ => EnigoButton::Left,
  }
}

fn rdev_button_name(button: RdevButton) -> String {
  match button {
    RdevButton::Right => "right",
    RdevButton::Middle => "middle",
    _ => "left",
  }
  .to_string()
}

fn button_label(button: &str) -> &str {
  match button {
    "right" => "右",
    "middle" => "中",
    _ => "左",
  }
}

fn describe_step(step: &ScriptStep) -> String {
  match step.kind.as_str() {
    "move" => format!("move to {},{}", step.x.unwrap_or_default(), step.y.unwrap_or_default()),
    "click" => format!("{} click", step.button.clone().unwrap_or_else(|| "left".to_string())),
    "wait" => format!("wait {}ms", step.duration_ms.unwrap_or_default()),
    "scroll" => format!("scroll {}", step.duration_ms.unwrap_or_default()),
    other => other.to_string(),
  }
}

fn lock_error<T>(error: std::sync::PoisonError<T>) -> String {
  error.to_string()
}
