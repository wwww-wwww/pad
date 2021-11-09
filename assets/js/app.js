import "phoenix_html"

function set_page(state) {
  pad_iframe.contentWindow.location.replace(state.page_url)
  header_title.textContent = state.page_name
  document.title = state.page_name
  Array.from(pads.children).forEach(pad => {
    pad.classList.toggle("selected", pad.getAttribute("data-page") == state.page_id)
  })
}

Array.from(pads.children).forEach(e => {
  const title = e.children[0].textContent
  e.children[0].removeAttribute("href")
  e.addEventListener("click", ev => {
    ev.preventDefault()

    const new_state = {
      page_id: e.getAttribute("data-page"),
      page_url: e.getAttribute("data-url"),
      page_name: title
    }

    history.pushState(new_state, "", new_state.page_id)
    set_page(new_state)
  })
})

const original_state = {
  page_id: document.getElementById("page_id").content,
  page_url: pad_iframe.src,
  page_name: header_title.textContent
}

window.addEventListener("popstate", e => {
  if (e.state) {
    set_page(e.state)
  } else {
    set_page(original_state)
  }
})

sidebar_filter.classList.toggle("hidden", false)

function filter() {
  const matched = []
  const unmatched = []
  const children = Array.from(pads.children)

  children.sort((a, b) => {
    const a_title = a.children[0].textContent
    const b_title = b.children[0].textContent

    const a_time = Number(a.getAttribute("data-time")) || 0
    const b_time = Number(b.getAttribute("data-time")) || 0
    const a_created = Number(a.getAttribute("data-created")) || 0
    const b_created = Number(b.getAttribute("data-created")) || 0
    const a_needed = Number(a.getAttribute("data-needed")) || 0
    const b_needed = Number(b.getAttribute("data-needed")) || 0

    switch (filter_sort.options[filter_sort.selectedIndex].value) {
      case "0":
        if (a_time > b_time) return -1
        if (b_time > a_time) return 1
        break
      case "1":
        if (a_needed > b_needed) return 1
        if (b_needed > a_needed) return -1
        break
      case "3":
        if (a_created > b_created) return -1
        if (b_created > a_created) return 1
        break
    }

    return a_title.localeCompare(b_title)
  })

  for (const e of children) {
    let is_matched = false
    for (let i = 0; i < e.children.length; i++) {
      const match = e.children[i].textContent.match(new RegExp(filter_text.value, "i"))
      if (match) {
        matched.push({ e: e, match: match, in: i })
        is_matched = true
        break
      }
    }

    if (!is_matched) {
      unmatched.push(e)
    }
  }

  children.forEach(e => {
    Array.from(e.children).forEach(c => c.textContent = c.textContent)
  })

  for (const e of matched) {
    if (e.e.classList.contains("pinned")) { continue }
    const text = e.e.children[e.in].textContent
    const p1 = text.slice(0, e.match.index)
    const p2 = text.slice(e.match.index, e.match.index + e.match[0].length)
    const p3 = text.slice(e.match.index + e.match[0].length)

    e.e.children[e.in].innerHTML = p1 + "<span class='highlight'>" + p2 + "</span>" + p3

    pads.appendChild(e.e)
  }
  for (const e of unmatched) {
    if (e.classList.contains("pinned")) { continue }
    pads.appendChild(e)
  }

  children.forEach(e => {
    e.classList.toggle("unmatched", unmatched.includes(e))
  })
}

filter_text.addEventListener("input", filter)
filter_sort.addEventListener("change", filter)
