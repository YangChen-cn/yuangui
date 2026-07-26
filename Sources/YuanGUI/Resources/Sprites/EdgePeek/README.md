# Edge peek sprites

以下六个紧裁 alpha PNG 由项目现有角色图作为身份与画风参考，通过
OpenAI 内置生图生成绿幕原图，再经本地 chroma-key 去背与 1 px 边缘收缩得到：

- `yuangui_edge_left.png`
- `yuangui_edge_right.png`
- `vcc_edge_left.png`
- `vcc_edge_right.png`
- `duo_edge_left.png`
- `duo_edge_right.png`

素材最长边为 512 px，横向只保留角色边界与 6 px 安全留白，不使用方形透明画布。
左右文件保留相同的透明原图，右侧显示由 SwiftUI 水平镜像，确保角色细节一致。
加载器会在素材缺失时回退到角色当前动作图。
