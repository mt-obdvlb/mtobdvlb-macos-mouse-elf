import { expect, test } from "@playwright/test";

test.describe("鼠标脚本精灵 agent smoke", () => {
  test("core workflow is operable in web preview", async ({ page }) => {
    await page.goto("/");

    await expect(page.getByRole("heading", { name: "鼠标脚本精灵" })).toBeVisible();
    await expect(page.getByText("定时点击、行为录制、脚本回放和安全停止")).toBeVisible();
    await expect(page.getByText("每隔 2.0 秒点击一次")).toBeVisible();

    await page.getByRole("button", { name: "右键" }).click();
    await page.getByLabel("重复次数").fill("3");
    await page.getByRole("button", { name: "启动" }).click();
    await expect(page.getByRole("button", { name: "停止" })).toBeVisible();
    await expect(page.getByText("运行中")).toBeVisible();
    await expect(page.getByText(/auto-click/)).toBeVisible();

    await page.getByRole("button", { name: "停止" }).click();
    await expect(page.getByRole("button", { name: "启动" })).toBeVisible();

    await page.getByRole("button", { name: "开始录制" }).click();
    await expect(page.getByRole("button", { name: "暂停录制" })).toBeVisible();
    await expect(page.getByText("录制中")).toBeVisible();
    await page.getByRole("button", { name: "暂停录制" }).click();
    await expect(page.getByRole("button", { name: "开始录制" })).toBeVisible();

    await page.getByRole("button", { name: "添加点击动作" }).click();
    await expect(page.getByText("新点击动作")).toBeVisible();

    await page.getByRole("tab", { name: "脚本库" }).click();
    await expect(page.getByText("网页表单重复提交")).toBeVisible();

    await page.getByRole("tab", { name: "运行日志" }).click();
    await expect(page.getByText(/current mode:/)).toBeVisible();
  });

  test("permission request path is visible to automation agents", async ({ page }) => {
    await page.goto("/");

    await expect(page.getByText("权限")).toBeVisible();
    await expect(page.getByRole("button", { name: "请求授权" })).toBeVisible();
    await expect(page.getByRole("button", { name: "重新检测" })).toBeVisible();

    await page.getByRole("button", { name: "请求授权" }).click();
    await expect(page.getByText("请在 Tauri 桌面模式中请求")).toBeVisible();
  });

  test("timeline steps can be created, edited, selected, and deleted", async ({ page }) => {
    await page.goto("/");

    await page.getByRole("button", { name: "添加移动动作" }).click();
    await expect(page.getByText("新移动动作")).toBeVisible();
    await page.getByRole("button", { name: "添加点击动作" }).click();
    await expect(page.getByText("新点击动作")).toBeVisible();
    await page.getByRole("button", { name: "添加等待动作" }).click();
    await expect(page.getByText("新等待动作")).toBeVisible();
    await page.getByRole("button", { name: "添加滚动动作" }).click();
    await expect(page.getByText("新滚动动作")).toBeVisible();

    await page.getByLabel("动作名称").fill("等待接口完成");
    await expect(page.getByText("等待接口完成")).toBeVisible();

    await page.getByRole("button", { name: /左键点击/ }).click();
    await page.getByLabel("动作名称").fill("确认按钮点击");
    await page.getByLabel("X 坐标").fill("900");
    await page.getByLabel("Y 坐标").fill("520");
    await expect(page.getByText("确认按钮点击")).toBeVisible();
    await expect(page.getByText("x:900 y:520 · left")).toBeVisible();

    await page.getByRole("button", { name: "删除当前步骤" }).click();
    await expect(page.getByText("确认按钮点击")).toHaveCount(0);
  });

  test("minimum desktop viewport has no horizontal layout overflow", async ({ page }) => {
    await page.setViewportSize({ width: 980, height: 640 });
    await page.goto("/");

    await expect(page.getByRole("heading", { name: "鼠标脚本精灵" })).toBeVisible();
    const hasHorizontalOverflow = await page.evaluate(
      () => document.documentElement.scrollWidth > window.innerWidth,
    );
    expect(hasHorizontalOverflow).toBe(false);
  });
});
