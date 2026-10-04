// The todo list, the same for the page and for EYG programs.

export interface Task {
  id: number;
  title: string;
  completed: boolean;
}

export class Tasks {
  items: Task[] = [];
  #next = 1;

  constructor(titles: string[] = []) {
    for (const title of titles) this.create(title);
  }

  create(title: string): number {
    const id = this.#next++;
    this.items.push({ id, title, completed: false });
    return id;
  }

  #update(id: number, change: Partial<Task>): boolean {
    const task = this.items.find((task) => task.id === id);
    if (!task) return false;
    Object.assign(task, change);
    return true;
  }

  rename(id: number, title: string) {
    return this.#update(id, { title });
  }

  setCompleted(id: number, completed: boolean) {
    return this.#update(id, { completed });
  }

  delete(id: number) {
    this.items = this.items.filter((task) => task.id !== id);
  }

  clearCompleted() {
    this.items = this.items.filter((task) => !task.completed);
  }

  completeAll(completed: boolean) {
    for (const task of this.items) task.completed = completed;
  }
}
