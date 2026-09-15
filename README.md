# Cursor ni eski holatiga qaytarish

Kompyuter qayta o‘rnatilgandan keyin Cursor sozlamalari, kengaytmalar va chatlarni tiklash.

Skript avval `C:\Users\Xp\Desktop\projects\cursor-backup` ni, keyin butun
`C:\Users\Xp\Desktop\projects` papkasini qidiradi (Cursor o‘zi backup olgan joy).

Cloud Agent sizning Windows diskingizga kira olmaydi. Shuning uchun tiklashni **shu kompyuterda**, Cursor yopiq holda ishga tushiring.

Eski Cursor dasturi o‘sha papkada emas — u yerda **sozlamalar, chatlar va kengaytmalar** turadi. Tiklagandan keyin Cursor ilovasini ochsangiz, avvalgi holat qaytadi.

## Qanday ishlatish

1. Cursor ni **to‘liq yoping** (pastki trey belgisini ham).
2. `restore-cursor.bat` ni ikki marta bosing.
3. Skript avval hozirgi (bo‘sh) holatni `Desktop\projects\cursor-pre-restore\` ga saqlaydi, keyin backupdan nusxa ko‘chiradi.
4. Cursor ni oching va **avvalgi hisob** bilan kiring.
5. Loyihalarni **eski papka yo‘lidan** oching. Chatlar yo‘lga bog‘liq.

Faqat nima topilishini ko‘rish:

```powershell
powershell -ExecutionPolicy Bypass -File .\restore-cursor.ps1 -Inventory
```

Boshqa papkadan tiklash:

```powershell
powershell -ExecutionPolicy Bypass -File .\restore-cursor.ps1 -BackupPath "D:\boshqa\cursor-backup"
```

Hech narsani o‘zgartirmasdan tekshirish:

```powershell
powershell -ExecutionPolicy Bypass -File .\restore-cursor.ps1 -WhatIf
```

## Nima tiklanadi

Backup ichidan topilsa, quyidagilar qaytadi:

- `settings.json`, `keybindings.json`, snippets
- Chat va agent tarixi (`state.vscdb`, `workspaceStorage`, `.cursor\projects`)
- Kengaytmalar (`.cursor\extensions`)
- MCP va boshqa Cursor sozlamalari (`.cursor`)

Kesh papkalari (`Cache`, `GPUCache`, `logs`) o‘tkazib yuboriladi.

## Backupda nima bo‘lishi kerak

Skript quyidagi tuzilmalarni taniydi:

```
cursor-backup\
  AppData\Roaming\Cursor\   yoki   Cursor\
  .cursor\                  yoki   Users\Xp\.cursor\
```

yoki oddiy fayllar:

```
cursor-backup\
  settings.json
  keybindings.json
  snippets\
```

Agar `restore-cursor.ps1 -Inventory` “Cursor sozlamalari topilmadi” desa, Explorer da backup papkasini ochib, ichida `Cursor`, `.cursor` yoki `settings.json` borligini tekshiring.

## Muhim

- Chatlar **eski loyiha yo‘liga** bog‘langan. Papka nomini o‘zgartirsangiz, suhbatlar chiqmasligi mumkin.
- Settings Sync conflict chiqsa, backupdagi sozlamalarni saqlang.
- Noto‘g‘ri tiklansa, `Desktop\projects\cursor-pre-restore\` dagi xavfsizlik nusxasidan qaytishingiz mumkin.
