"use client";

import {
  Activity,
  Bot,
  CircleDot,
  Clock3,
  Crosshair,
  FileCode2,
  Gauge,
  Hand,
  Keyboard,
  MousePointer2,
  Pause,
  Play,
  Plus,
  Power,
  Radio,
  RotateCcw,
  Save,
  ScrollText,
  Settings2,
  ShieldCheck,
  Square,
  TimerReset,
  Trash2,
  Wand2,
} from "lucide-react";
import { invoke } from "@tauri-apps/api/core";
import { useEffect, useMemo, useState } from "react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Progress } from "@/components/ui/progress";
import { Separator } from "@/components/ui/separator";
import { Slider } from "@/components/ui/slider";
import { Switch } from "@/components/ui/switch";
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import { cn } from "@/lib/utils";

type ViewId = "tasks" | "recording" | "library" | "settings";
type StepKind = "move" | "click" | "wait" | "scroll";
type ScriptStep = {
  id: string;
  kind: StepKind;
  label: string;
  x?: number;
  y?: number;
  button?: "left" | "right" | "middle";
  durationMs?: number;
};

type AutomationStatus = {
  running: boolean;
  mode: string;
  last_action: string;
};

const initialSteps: ScriptStep[] = [
  {
    id: "s1",
    kind: "move",
    label: "移动到提交按钮",
    x: 842,
    y: 516,
    durationMs: 180,
  },
  {
    id: "s2",
    kind: "click",
    label: "左键点击",
    x: 842,
    y: 516,
    button: "left",
  },
  {
    id: "s3",
    kind: "wait",
    label: "等待页面响应",
    durationMs: 900,
  },
  {
    id: "s4",
    kind: "scroll",
    label: "向下滚动",
    durationMs: 320,
  },
];

const navigation: Array<{
  id: ViewId;
  label: string;
  icon: typeof Bot;
}> = [
  { id: "tasks", label: "任务", icon: Bot },
  { id: "recording", label: "录制", icon: CircleDot },
  { id: "library", label: "脚本库", icon: FileCode2 },
  { id: "settings", label: "设置", icon: Settings2 },
];

const viewCopy: Record<ViewId, { title: string; subtitle: string }> = {
  tasks: {
    title: "任务",
    subtitle: "只处理定时点击任务和当前运行状态",
  },
  recording: {
    title: "录制",
    subtitle: "录制鼠标行为、编辑步骤并回放脚本",
  },
  library: {
    title: "脚本库",
    subtitle: "管理可复用的鼠标脚本模板",
  },
  settings: {
    title: "设置",
    subtitle: "权限、安全策略、快捷键和运行日志",
  },
};

const scriptPresets = [
  { name: "网页表单重复提交", count: 7, hotkey: "⌘⇧1", updated: "今天" },
  { name: "游戏挂机轻点", count: 3, hotkey: "⌘⇧2", updated: "昨天" },
  { name: "批量确认弹窗", count: 5, hotkey: "⌘⇧3", updated: "2 天前" },
];

function isTauriRuntime() {
  return typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;
}

async function callTauri<T>(command: string, args?: Record<string, unknown>) {
  if (!isTauriRuntime()) {
    return null;
  }

  return invoke<T>(command, args);
}

function sliderNumber(value: number | readonly number[], fallback: number) {
  return Array.isArray(value) ? Number(value[0] ?? fallback) : Number(value);
}

export default function Home() {
  const [activeView, setActiveView] = useState<ViewId>("tasks");
  const [intervalSeconds, setIntervalSeconds] = useState(2);
  const [repeat, setRepeat] = useState(0);
  const [button, setButton] = useState<"left" | "right" | "middle">("left");
  const [safeStop, setSafeStop] = useState(true);
  const [isClicking, setIsClicking] = useState(false);
  const [isRecording, setIsRecording] = useState(false);
  const [isPlaying, setIsPlaying] = useState(false);
  const [steps, setSteps] = useState(initialSteps);
  const [selectedStepId, setSelectedStepId] = useState(initialSteps[1].id);
  const [status, setStatus] = useState<AutomationStatus>({
    running: false,
    mode: "idle",
    last_action: "本地预览模式",
  });
  const [accessibilityGranted, setAccessibilityGranted] = useState(false);
  const [permissionMessage, setPermissionMessage] = useState("Web 预览未检测");

  const selectedStep = steps.find((step) => step.id === selectedStepId) ?? steps[0];
  const totalDuration = useMemo(
    () => steps.reduce((sum, step) => sum + (step.durationMs ?? 120), 0),
    [steps],
  );
  const progressValue = isPlaying ? 62 : isRecording ? 34 : isClicking ? 48 : 0;

  useEffect(() => {
    void refreshAccessibilityPermission();
  }, []);

  async function refreshAccessibilityPermission() {
    const granted = await callTauri<boolean>("accessibility_permission_status");
    if (granted === null) {
      setAccessibilityGranted(false);
      setPermissionMessage("Web 预览");
      return;
    }

    setAccessibilityGranted(granted);
    setPermissionMessage(granted ? "已授权" : "待授权");
  }

  async function requestAccessibilityPermission() {
    const granted = await callTauri<boolean>("request_accessibility_permission");
    if (granted === null) {
      setPermissionMessage("请在 Tauri 桌面模式中请求");
      return;
    }

    setAccessibilityGranted(granted);
    setPermissionMessage(granted ? "已授权" : "已发起系统请求");
  }

  async function startClicker() {
    setIsClicking(true);
    const nextStatus =
      (await callTauri<AutomationStatus>("start_auto_click", {
        config: {
          intervalMs: Math.round(intervalSeconds * 1000),
          button,
          repeat,
        },
      })) ??
      ({
        running: true,
        mode: "auto-click",
        last_action: `interval=${intervalSeconds}s button=${button} repeat=${repeat}`,
      } satisfies AutomationStatus);
    setStatus(nextStatus);
  }

  async function stopClicker() {
    setIsClicking(false);
    setIsPlaying(false);
    const nextStatus =
      (await callTauri<AutomationStatus>("stop_auto_click")) ??
      ({
        running: false,
        mode: "idle",
        last_action: "stopped",
      } satisfies AutomationStatus);
    setStatus(nextStatus);
  }

  async function playback() {
    setIsPlaying(true);
    const nextStatus =
      (await callTauri<AutomationStatus>("playback_script", { steps })) ??
      ({
        running: true,
        mode: "playback",
        last_action: `${steps.length} steps queued`,
      } satisfies AutomationStatus);
    setStatus(nextStatus);
  }

  async function toggleRecording() {
    if (isRecording) {
      setIsRecording(false);
      const recordedSteps =
        (await callTauri<ScriptStep[]>("stop_recording")) ?? steps;
      if (recordedSteps.length > 0) {
        setSteps(recordedSteps);
        setSelectedStepId(recordedSteps[0].id);
      }
      setStatus({
        running: false,
        mode: "idle",
        last_action: `recording stopped, ${recordedSteps.length} steps`,
      });
      return;
    }

    setIsRecording(true);
    const nextStatus =
      (await callTauri<AutomationStatus>("start_recording")) ??
      ({
        running: true,
        mode: "recording",
        last_action: "recording mouse events",
      } satisfies AutomationStatus);
    setStatus(nextStatus);
  }

  function addStep(kind: StepKind) {
    const nextStep: ScriptStep = {
      id: crypto.randomUUID(),
      kind,
      label:
        kind === "click"
          ? "新点击动作"
          : kind === "move"
            ? "新移动动作"
            : kind === "scroll"
              ? "新滚动动作"
              : "新等待动作",
      x: kind === "wait" || kind === "scroll" ? undefined : 640,
      y: kind === "wait" || kind === "scroll" ? undefined : 420,
      button: kind === "click" ? button : undefined,
      durationMs: kind === "click" ? undefined : 300,
    };
    setSteps((current) => [...current, nextStep]);
    setSelectedStepId(nextStep.id);
    setActiveView("recording");
  }

  function removeSelectedStep() {
    const nextSteps = steps.filter((step) => step.id !== selectedStepId);
    setSteps(nextSteps);
    setSelectedStepId(nextSteps[0]?.id ?? "");
  }

  return (
    <main className="min-h-screen bg-background text-foreground">
      <div className="grid h-screen grid-cols-[76px_minmax(904px,1fr)] overflow-hidden">
        <aside className="flex flex-col border-r border-border bg-sidebar">
          <div className="flex h-16 items-center justify-center">
            <div className="flex size-9 items-center justify-center rounded-lg bg-primary text-primary-foreground">
              <MousePointer2 />
            </div>
          </div>
          <nav className="flex flex-1 flex-col items-center gap-2 px-2 py-3">
            {navigation.map((item) => {
              const Icon = item.icon;
              const active = item.id === activeView;
              return (
                <Tooltip key={item.id}>
                  <TooltipTrigger
                    aria-label={`导航-${item.label}`}
                    aria-current={active ? "page" : undefined}
                    className={cn(
                      "flex size-11 items-center justify-center rounded-lg text-sidebar-foreground/60 transition-colors hover:bg-sidebar-accent hover:text-sidebar-foreground",
                      active &&
                        "bg-sidebar-accent text-sidebar-foreground ring-1 ring-border",
                    )}
                    onClick={() => setActiveView(item.id)}
                  >
                    <Icon />
                  </TooltipTrigger>
                  <TooltipContent side="right">{item.label}</TooltipContent>
                </Tooltip>
              );
            })}
          </nav>
          <div className="flex h-16 items-center justify-center border-t border-border">
            <Badge variant={isTauriRuntime() ? "default" : "secondary"}>
              {isTauriRuntime() ? "Tauri" : "Web"}
            </Badge>
          </div>
        </aside>

        <section className="flex min-w-0 flex-col">
          <header className="flex h-16 items-center justify-between border-b border-border px-6">
            <div className="flex items-center gap-3">
              <div>
                <h1 className="text-xl font-semibold tracking-tight">
                  {viewCopy[activeView].title}
                </h1>
                <p className="text-xs text-muted-foreground">
                  {viewCopy[activeView].subtitle}
                </p>
              </div>
              <Badge variant="outline">v0.1 desktop</Badge>
            </div>
            <div className="flex items-center gap-2">
              <Button variant="outline" size="sm">
                <Save data-icon="inline-start" />
                保存脚本
              </Button>
              <Button
                size="sm"
                variant={isClicking || isPlaying ? "destructive" : "default"}
                onClick={isClicking || isPlaying ? stopClicker : startClicker}
              >
                {isClicking || isPlaying ? (
                  <Square data-icon="inline-start" />
                ) : (
                  <Power data-icon="inline-start" />
                )}
                {isClicking || isPlaying ? "停止" : "启动"}
              </Button>
            </div>
          </header>

          {activeView === "tasks" && (
            <TasksView
              button={button}
              intervalSeconds={intervalSeconds}
              isClicking={isClicking}
              progressValue={progressValue}
              repeat={repeat}
              safeStop={safeStop}
              status={status}
              setButton={setButton}
              setIntervalSeconds={setIntervalSeconds}
              setRepeat={setRepeat}
              setSafeStop={setSafeStop}
              startClicker={startClicker}
              stopClicker={stopClicker}
            />
          )}

          {activeView === "recording" && (
            <RecordingView
              isRecording={isRecording}
              isPlaying={isPlaying}
              progressValue={progressValue}
              selectedStep={selectedStep}
              selectedStepId={selectedStepId}
              steps={steps}
              totalDuration={totalDuration}
              addStep={addStep}
              playback={playback}
              removeSelectedStep={removeSelectedStep}
              resetSteps={() => {
                setSteps(initialSteps);
                setSelectedStepId(initialSteps[1].id);
              }}
              setSelectedStepId={setSelectedStepId}
              setSteps={setSteps}
              toggleRecording={toggleRecording}
            />
          )}

          {activeView === "library" && <LibraryView setActiveView={setActiveView} />}

          {activeView === "settings" && (
            <SettingsView
              accessibilityGranted={accessibilityGranted}
              permissionMessage={permissionMessage}
              safeStop={safeStop}
              status={status}
              refreshAccessibilityPermission={refreshAccessibilityPermission}
              requestAccessibilityPermission={requestAccessibilityPermission}
              setSafeStop={setSafeStop}
            />
          )}
        </section>
      </div>
    </main>
  );
}

function TasksView({
  button,
  intervalSeconds,
  isClicking,
  progressValue,
  repeat,
  safeStop,
  status,
  setButton,
  setIntervalSeconds,
  setRepeat,
  setSafeStop,
  startClicker,
  stopClicker,
}: {
  button: "left" | "right" | "middle";
  intervalSeconds: number;
  isClicking: boolean;
  progressValue: number;
  repeat: number;
  safeStop: boolean;
  status: AutomationStatus;
  setButton: (button: "left" | "right" | "middle") => void;
  setIntervalSeconds: (value: number) => void;
  setRepeat: (value: number) => void;
  setSafeStop: (value: boolean) => void;
  startClicker: () => void;
  stopClicker: () => void;
}) {
  return (
    <div className="grid min-h-0 flex-1 grid-cols-[minmax(0,1fr)_280px] gap-5 overflow-auto p-6">
      <section className="rounded-lg border border-border bg-card/70 p-6 shadow-sm">
        <div className="flex items-start justify-between gap-6">
          <div className="flex flex-col gap-1">
            <div className="flex items-center gap-2 text-sm text-muted-foreground">
              <TimerReset />
              定时点击任务
            </div>
            <h2 className="text-2xl font-semibold tracking-tight">
              每隔 {intervalSeconds.toFixed(1)} 秒点击一次
            </h2>
          </div>
          <Badge variant={isClicking ? "default" : "secondary"}>
            {isClicking ? "运行中" : "待机"}
          </Badge>
        </div>

        <div className="mt-8 grid grid-cols-[minmax(0,1fr)_160px] gap-6">
          <div className="flex flex-col gap-5">
            <div className="flex flex-col gap-2">
              <div className="flex items-center justify-between text-xs text-muted-foreground">
                <span>点击间隔</span>
                <span>{intervalSeconds.toFixed(1)}s</span>
              </div>
              <Slider
                min={0.2}
                max={10}
                step={0.1}
                value={[intervalSeconds]}
                onValueChange={(value) =>
                  setIntervalSeconds(sliderNumber(value, 1))
                }
              />
            </div>
            <div className="grid grid-cols-3 gap-3">
              {(["left", "right", "middle"] as const).map((item) => (
                <Button
                  key={item}
                  variant={button === item ? "default" : "outline"}
                  onClick={() => setButton(item)}
                >
                  <Hand data-icon="inline-start" />
                  {item === "left" ? "左键" : item === "right" ? "右键" : "中键"}
                </Button>
              ))}
            </div>
            <Progress value={progressValue} />
          </div>

          <div className="flex flex-col gap-3">
            <label className="flex flex-col gap-1 text-xs text-muted-foreground">
              重复次数
              <Input
                value={repeat}
                onChange={(event) => setRepeat(Number(event.target.value || 0))}
                type="number"
                min={0}
              />
            </label>
            <div className="flex items-center justify-between rounded-lg bg-muted/50 px-3 py-2">
              <span className="text-xs text-muted-foreground">移到角落停止</span>
              <Switch checked={safeStop} onCheckedChange={setSafeStop} />
            </div>
            <Button
              className="mt-auto"
              variant={isClicking ? "destructive" : "default"}
              onClick={isClicking ? stopClicker : startClicker}
            >
              {isClicking ? <Square data-icon="inline-start" /> : <Power data-icon="inline-start" />}
              {isClicking ? "停止任务" : "启动任务"}
            </Button>
          </div>
        </div>
      </section>

      <aside className="rounded-lg border border-border bg-card/50 p-5">
        <div className="flex items-center gap-2 text-sm font-medium">
          <Activity />
          当前状态
        </div>
        <div className="mt-5 flex flex-col gap-4 text-sm">
          <StatusRow label="模式" value={status.mode} />
          <StatusRow label="动作" value={status.last_action} />
          <StatusRow label="按键" value={button} />
          <StatusRow label="重复" value={repeat === 0 ? "无限" : `${repeat} 次`} />
        </div>
      </aside>
    </div>
  );
}

function RecordingView({
  isRecording,
  isPlaying,
  progressValue,
  selectedStep,
  selectedStepId,
  steps,
  totalDuration,
  addStep,
  playback,
  removeSelectedStep,
  resetSteps,
  setSelectedStepId,
  setSteps,
  toggleRecording,
}: {
  isRecording: boolean;
  isPlaying: boolean;
  progressValue: number;
  selectedStep?: ScriptStep;
  selectedStepId: string;
  steps: ScriptStep[];
  totalDuration: number;
  addStep: (kind: StepKind) => void;
  playback: () => void;
  removeSelectedStep: () => void;
  resetSteps: () => void;
  setSelectedStepId: (id: string) => void;
  setSteps: React.Dispatch<React.SetStateAction<ScriptStep[]>>;
  toggleRecording: () => void;
}) {
  return (
    <div className="grid min-h-0 flex-1 grid-cols-[minmax(0,1fr)_320px] overflow-hidden">
      <div className="grid min-h-0 grid-rows-[auto_minmax(260px,1fr)] gap-5 overflow-auto p-6">
        <section className="rounded-lg border border-border bg-card/70 p-5 shadow-sm">
          <div className="flex items-start justify-between gap-4">
            <div className="flex flex-col gap-1">
              <div className="flex items-center gap-2 text-sm text-muted-foreground">
                <Radio />
                录制与回放
              </div>
              <h2 className="text-2xl font-semibold tracking-tight">
                {steps.length} 个动作，{(totalDuration / 1000).toFixed(1)} 秒
              </h2>
            </div>
            <Badge variant={isRecording ? "default" : "outline"}>
              {isRecording ? "录制中" : isPlaying ? "回放中" : "未录制"}
            </Badge>
          </div>
          <div className="mt-6 flex flex-col gap-4">
            <Progress value={progressValue} />
            <div className="grid grid-cols-3 gap-3">
              <Button
                variant={isRecording ? "destructive" : "outline"}
                onClick={toggleRecording}
              >
                {isRecording ? (
                  <Pause data-icon="inline-start" />
                ) : (
                  <CircleDot data-icon="inline-start" />
                )}
                {isRecording ? "暂停录制" : "开始录制"}
              </Button>
              <Button variant="outline" onClick={playback}>
                <Play data-icon="inline-start" />
                回放
              </Button>
              <Button variant="outline" onClick={resetSteps}>
                <RotateCcw data-icon="inline-start" />
                重置
              </Button>
            </div>
            <div className="grid grid-cols-4 gap-2">
              {(["move", "click", "wait", "scroll"] as const).map((kind) => (
                <Button
                  key={kind}
                  variant="secondary"
                  size="sm"
                  aria-label={`添加${
                    kind === "move"
                      ? "移动"
                      : kind === "click"
                        ? "点击"
                        : kind === "wait"
                          ? "等待"
                          : "滚动"
                  }动作`}
                  onClick={() => addStep(kind)}
                >
                  <Plus data-icon="inline-start" />
                  {kind === "move"
                    ? "移动"
                    : kind === "click"
                      ? "点击"
                      : kind === "wait"
                        ? "等待"
                        : "滚动"}
                </Button>
              ))}
            </div>
          </div>
        </section>

        <Timeline
          selectedStepId={selectedStepId}
          steps={steps}
          setSelectedStepId={setSelectedStepId}
        />
      </div>

      <StepInspector
        selectedStep={selectedStep}
        removeSelectedStep={removeSelectedStep}
        setSteps={setSteps}
      />
    </div>
  );
}

function Timeline({
  selectedStepId,
  steps,
  setSelectedStepId,
}: {
  selectedStepId: string;
  steps: ScriptStep[];
  setSelectedStepId: (id: string) => void;
}) {
  return (
    <section className="min-h-0 rounded-lg border border-border bg-card/70 shadow-sm">
      <div className="flex h-12 items-center justify-between border-b border-border px-4">
        <h2 className="text-sm font-semibold">时间线</h2>
        <span className="text-xs text-muted-foreground">共 {steps.length} 步</span>
      </div>
      <div className="grid grid-cols-[96px_minmax(0,1fr)_120px] border-b border-border px-4 py-2 text-xs text-muted-foreground">
        <span>类型</span>
        <span>动作</span>
        <span>耗时</span>
      </div>
      <div className="flex max-h-[390px] flex-col overflow-auto">
        {steps.map((step, index) => (
          <button
            key={step.id}
            className={cn(
              "grid grid-cols-[96px_minmax(0,1fr)_120px] items-center border-b border-border/70 px-4 py-3 text-left transition-colors hover:bg-muted/40",
              selectedStepId === step.id && "bg-primary/10",
            )}
            onClick={() => setSelectedStepId(step.id)}
          >
            <span className="flex items-center gap-2 text-xs text-muted-foreground">
              {step.kind === "move" && <Crosshair />}
              {step.kind === "click" && <MousePointer2 />}
              {step.kind === "wait" && <Clock3 />}
              {step.kind === "scroll" && <ScrollText />}
              {index + 1}
            </span>
            <span className="flex min-w-0 flex-col gap-1">
              <span className="truncate text-sm font-medium">{step.label}</span>
              <span className="truncate text-xs text-muted-foreground">
                {step.x !== undefined && step.y !== undefined
                  ? `x:${step.x} y:${step.y}`
                  : "无坐标"}{" "}
                {step.button ? `· ${step.button}` : ""}
              </span>
            </span>
            <span className="font-mono text-xs text-muted-foreground">
              {step.durationMs ? `${step.durationMs}ms` : "instant"}
            </span>
          </button>
        ))}
      </div>
    </section>
  );
}

function StepInspector({
  selectedStep,
  removeSelectedStep,
  setSteps,
}: {
  selectedStep?: ScriptStep;
  removeSelectedStep: () => void;
  setSteps: React.Dispatch<React.SetStateAction<ScriptStep[]>>;
}) {
  return (
    <aside className="flex min-w-0 flex-col border-l border-border bg-card/50">
      <div className="flex h-16 items-center justify-between border-b border-border px-5">
        <div>
          <h2 className="text-sm font-semibold">步骤检查器</h2>
          <p className="text-xs text-muted-foreground">编辑当前脚本动作</p>
        </div>
        <Button
          aria-label="删除当前步骤"
          variant="ghost"
          size="icon-sm"
          onClick={removeSelectedStep}
          disabled={!selectedStep}
        >
          <Trash2 />
        </Button>
      </div>

      {selectedStep ? (
        <div className="flex flex-1 flex-col gap-5 overflow-auto p-5">
          <div className="flex flex-col gap-2">
            <label className="text-xs text-muted-foreground">动作名称</label>
            <Input
              aria-label="动作名称"
              value={selectedStep.label}
              onChange={(event) =>
                setSteps((current) =>
                  current.map((step) =>
                    step.id === selectedStep.id
                      ? { ...step, label: event.target.value }
                      : step,
                  ),
                )
              }
            />
          </div>

          <div className="grid grid-cols-2 gap-3">
            <label className="flex flex-col gap-2 text-xs text-muted-foreground">
              X 坐标
              <Input
                value={selectedStep.x ?? ""}
                onChange={(event) =>
                  setSteps((current) =>
                    current.map((step) =>
                      step.id === selectedStep.id
                        ? { ...step, x: Number(event.target.value || 0) }
                        : step,
                    ),
                  )
                }
              />
            </label>
            <label className="flex flex-col gap-2 text-xs text-muted-foreground">
              Y 坐标
              <Input
                value={selectedStep.y ?? ""}
                onChange={(event) =>
                  setSteps((current) =>
                    current.map((step) =>
                      step.id === selectedStep.id
                        ? { ...step, y: Number(event.target.value || 0) }
                        : step,
                    ),
                  )
                }
              />
            </label>
          </div>

          <div className="flex flex-col gap-3">
            <div className="flex items-center justify-between text-xs text-muted-foreground">
              <span>持续时间</span>
              <span>{selectedStep.durationMs ?? 0}ms</span>
            </div>
            <Slider
              min={0}
              max={3000}
              step={50}
              value={[selectedStep.durationMs ?? 0]}
              onValueChange={(value) =>
                setSteps((current) =>
                  current.map((step) =>
                    step.id === selectedStep.id
                      ? { ...step, durationMs: sliderNumber(value, 0) }
                      : step,
                  ),
                )
              }
            />
          </div>
        </div>
      ) : (
        <div className="flex flex-1 flex-col items-center justify-center gap-3 text-muted-foreground">
          <Wand2 />
          <p className="text-sm">没有选中的步骤</p>
        </div>
      )}
    </aside>
  );
}

function LibraryView({ setActiveView }: { setActiveView: (view: ViewId) => void }) {
  return (
    <div className="min-h-0 flex-1 overflow-auto p-6">
      <section className="rounded-lg border border-border bg-card/70 shadow-sm">
        <div className="flex h-12 items-center justify-between border-b border-border px-4">
          <h2 className="text-sm font-semibold">脚本库</h2>
          <Button size="sm" onClick={() => setActiveView("recording")}>
            <Plus data-icon="inline-start" />
            新建脚本
          </Button>
        </div>
        <div className="grid grid-cols-3 gap-3 p-4">
          {scriptPresets.map((script) => (
            <button
              key={script.name}
              className="flex min-h-32 flex-col gap-3 rounded-lg border border-border bg-background/40 p-4 text-left transition-colors hover:bg-muted/40"
              onClick={() => setActiveView("recording")}
            >
              <FileCode2 />
              <span className="text-sm font-medium">{script.name}</span>
              <span className="text-xs text-muted-foreground">
                {script.count} 步 · {script.hotkey}
              </span>
              <span className="mt-auto text-xs text-muted-foreground">
                更新于 {script.updated}
              </span>
            </button>
          ))}
        </div>
      </section>
    </div>
  );
}

function SettingsView({
  accessibilityGranted,
  permissionMessage,
  safeStop,
  status,
  refreshAccessibilityPermission,
  requestAccessibilityPermission,
  setSafeStop,
}: {
  accessibilityGranted: boolean;
  permissionMessage: string;
  safeStop: boolean;
  status: AutomationStatus;
  refreshAccessibilityPermission: () => void;
  requestAccessibilityPermission: () => void;
  setSafeStop: (value: boolean) => void;
}) {
  return (
    <div className="grid min-h-0 flex-1 grid-cols-[minmax(0,1fr)_300px] gap-5 overflow-auto p-6">
      <section className="rounded-lg border border-border bg-card/70 p-5 shadow-sm">
        <div className="flex items-center gap-2 text-sm font-medium">
          <ShieldCheck />
          安全与权限
        </div>

        <div className="mt-5 grid grid-cols-2 gap-4">
          <div className="rounded-lg bg-muted/40 p-4">
            <div className="flex items-center gap-2 text-xs text-muted-foreground">
              <Gauge />
              辅助功能权限
            </div>
            <p className="mt-3 text-lg font-medium">
              {accessibilityGranted ? "已授权" : permissionMessage}
            </p>
            <div className="mt-4 grid grid-cols-2 gap-3">
              <Button variant="outline" onClick={requestAccessibilityPermission}>
                <ShieldCheck data-icon="inline-start" />
                请求授权
              </Button>
              <Button variant="secondary" onClick={refreshAccessibilityPermission}>
                <Gauge data-icon="inline-start" />
                重新检测
              </Button>
            </div>
          </div>

          <div className="rounded-lg bg-muted/40 p-4">
            <div className="flex items-center gap-2 text-xs text-muted-foreground">
              <Keyboard />
              快捷键
            </div>
            <p className="mt-3 font-mono text-lg">⌘⇧M</p>
            <p className="mt-2 text-xs text-muted-foreground">
              后续用于全局启动和停止脚本。
            </p>
          </div>
        </div>

        <Separator className="my-5" />

        <div className="grid grid-cols-2 gap-4">
          <div className="flex items-center justify-between rounded-lg bg-muted/40 px-4 py-3">
            <span className="text-sm">坐标越界停止</span>
            <Switch checked={safeStop} onCheckedChange={setSafeStop} />
          </div>
          <div className="flex items-center justify-between rounded-lg bg-muted/40 px-4 py-3">
            <span className="text-sm">回放前倒计时</span>
            <Switch defaultChecked />
          </div>
        </div>
      </section>

      <aside className="rounded-lg border border-border bg-card/50 p-5">
        <div className="flex items-center gap-2 text-sm font-medium">
          <Activity />
          运行日志
        </div>
        <div className="mt-4 rounded-lg bg-background/50 p-4 font-mono text-xs text-muted-foreground">
          <p>[19:23:02] shell initialized: Next.js + Tauri</p>
          <p>[19:23:08] command boundary: start_auto_click</p>
          <p>[19:23:10] safe stop: {safeStop ? "enabled" : "disabled"}</p>
          <p>[19:23:15] current mode: {status.mode}</p>
        </div>
      </aside>
    </div>
  );
}

function StatusRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-start justify-between gap-3 border-b border-border/70 pb-3 last:border-0 last:pb-0">
      <span className="text-muted-foreground">{label}</span>
      <span className="max-w-40 text-right font-mono text-xs">{value}</span>
    </div>
  );
}
