path = "lib/dale_app_web/components/layouts/root.html.heex"

with open(path, "r", encoding="utf-8") as f:
    lines = f.readlines()

# borra las líneas 233 a 241 (índices 232 a 240)
del lines[232:241]

with open(path, "w", encoding="utf-8") as f:
    f.writelines(lines)

print("Listo: líneas duplicadas eliminadas")
