# README i18n workflow

This folder is the single source of truth for the GitHub homepage READMEs.

## Edit content

Update localized copy in:

- `tool/readme_i18n/locales.json`

## Edit layout

Update the shared landing-page template in:

- `tool/readme_i18n/template.md`

## Regenerate everything

From the repository root:

```powershell
python .\tool\readme_i18n\render.py
```

Or use the Windows helper:

```powershell
.\tool\readme_i18n\render_all.ps1
```

## Verify generated output

```powershell
python .\tool\readme_i18n\render.py --check
```

## Generated assets

The render step also refreshes localized section banners under:

- `docs/readme/generated/<locale>/`

Those generated files are committed so GitHub can render them directly.
