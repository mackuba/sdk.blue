document.addEventListener('DOMContentLoaded', () => {
  let tagCloud = document.getElementById('tag_cloud');
  let tagButtons = Array.from(tagCloud.querySelectorAll('span[data-tag]'));
  let languageSections = Array.from(document.querySelectorAll('.language'));

  let activeTag = null;

  for (let button of tagButtons) {
    button.addEventListener('click', (event) => {
      let tagValue = button.dataset.tag;
      activeTag = (activeTag === tagValue) ? null : tagValue;

      tagButtons.forEach(button => {
        button.classList.toggle('selected', button.dataset.tag === activeTag);
      });

      languageSections.forEach(section => {
        let projectItems = Array.from(section.querySelectorAll('.projects > li'));
        let anyMatched = false;

        for (let project of projectItems) {
          let projectTags = project.dataset.tags ? project.dataset.tags.split(',') : [];
          let match = !activeTag || projectTags.includes(activeTag);

          project.style.display = match ? '' : 'none';
          anyMatched = anyMatched || match;
        }

        section.style.display = anyMatched ? '' : 'none';
      });
    });
  }
});
