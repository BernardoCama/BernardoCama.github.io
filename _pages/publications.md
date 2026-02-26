---
layout: page
permalink: /publications/
title: publications
description: Publications in reverse chronological order.
nav: true
nav_order: 2
---

<!-- _pages/publications.md -->

<!-- Bibsearch Feature -->

{% include bib_search.liquid %}

{% if site.data.citations.metadata.last_updated %}

<p class="text-muted mt-3 small">
  <i class="fas fa-sync-alt mr-1"></i> Citation counts last updated: {{ site.data.citations.metadata.last_updated }}
</p>
{% endif %}

<div class="publications">

{% bibliography %}

</div>
