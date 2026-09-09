# SMDG Ocean Terminals + Co-located BIC Facility Codes (Sample Set)

Source: https://github.com/bic-org/geofence-library (`geofence-data/`)
Snapshot: commit `98452a2`, 2026-09-08.

## Scope

SMDG ocean terminal geofence in the library, BIC Facility Code (BFC) geofences at each of the same UNLOCODEs, from a sample set of the main data.

## Layout

```
smdg/<CODE>-SMDG.json     730 files — SMDG ocean terminals
bic/<CODE>-BIC.json     1,072 files - BIC Facility Codes
index.csv                 one row per file
```

Files are unmodified copies of the upstream GeoJSON `FeatureCollection`s. Both code
lists are UNLOCODE children, so the first 5 characters of any filename give the port
area — `NLRTM*` returns everything in Rotterdam across both providers.

## index.csv columns

`unlocode`, `code`, `codeProvider`, `file`, `features`, `categories`, `sections`,
`trustGrade`, `version`

## Notes on the data

- **Feature categories**: SMDG terminals typically carry `FACILITY` + `BERTH` +
  `CENTROID` across numbered `section`s; BFCs are usually `FACILITY` + `CENTROID`.
- **Trust grades**: LOCAL_KNOWLEDGE 1,056, REVIEW_PANEL 607, FACILITY_PROVIDED 103,
  **absent 36**. Repo-wide 239 of 5,002 files carry no `trustGrade`, so treat the
  field as optional when parsing.
- **Versions** span 2023-01-05 to 2026-09-08.

## Versioning of Geofences

All published geofences are given a version number based upon the date of publication (following review), this version number will be attached to each 'feature' in the geofence and follows the date structure `YYYY-MM-DD` for example: `2024-01-02` for the 2nd of January 2024.  These versions will be stamped into the meta data as described below, allowing you to identify the version number of the geofence and compare to your current version.

## Metadata Properties

All features within the collection will hold a `properties` section as example below:

```
"properties": {
    "code": "BEANREBOT",
    "codeProvider": "BIC",
    "trustGrade": "LOCAL_KNOWLEDGE",
    "section": "1",
    "category": "geofence",
    "version": "2023-10-25",
    "url": "https://www.bic-code.org/facility-codes/beanrebot/"
}
```

* `code` refers to the coded value for this facility, this is typically found in EDI or API messages that make use of the BIC Facility Code and SMDG Ocean Terminal codes such as sailing schedules, or gate movement messages, allowing you to link the geofence and position of equipment to messages used within transport and logistics.
* `codeProvider` identifies either BIC or SMDG as code list provider
* `trustGrade` will be one of either `FACILITY_PROVIDED`, `LOCAL_KNOWLEDGE` or `REVIEW_PANEL` this is how the geofence was presented at time of approval.  Note facility provided are verified by their email.
* `category` you will always see a `FACILITY` which relates to the core area and for an SMDG the land based part of the terminal, you may optionally also see `BERTH` which for SMDG facilities is the berthing area for container vessels at that container terminal.
* `version` as described above the version number applied at time of publication.
`url` pointer to a human friendly url to view the facility
